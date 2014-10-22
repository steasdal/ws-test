<!DOCTYPE html>

<html>
<head>
    <meta name="layout" content="main"/>

    <asset:javascript src="jquery" />
    <asset:javascript src="spring-websocket" />
    <asset:javascript src="adapter.js" />
    <asset:stylesheet href="chat.css"/>

    <script type="text/javascript">
        $(function() {
            var chatId = $("#chatId").val();
            var name = $("#name").val();

            var convoDiv = $("#conversationDiv");

            var socket = new SockJS("${createLink(uri: '/stomp')}");
            var client = Stomp.over(socket);

            var privateSubscription, publicSubscription, registrationSubscription, rtcMessageSubscription;

            var localVideo = $("#localVideo")[0];
            var remoteVideo = $("#remoteVideo")[0];

            var chatButton = $("#rtcChatButton");
            var hangupButton = $("#rtcHangupButton");

            var localStream, remoteStream, rtcPeerConnection;
            var isInitiator = false;
            var isStarted = false;

            var remoteChatter = undefined;

            var rtcConstraints = {video: true, audio:true};

            // We'll use Google's unofficial public STUN server (NO TURN support!)
            var rtcConfiguration = {'iceServers': [{'url': 'stun:stun.l.google.com:19302'}]};

            client.connect({}, function() {

                // Register the existence of this new chat client with the server
                var json = {"name": name, "chatId": chatId};
                client.send("/app/register", {}, JSON.stringify(json));

                // Subscribe to the public channel at /topic/public
                publicSubscription = client.subscribe("/topic/public", function(message) {
                    var messageBody = JSON.parse(message.body);

                    var newMessage = "Public message from " + messageBody.name + ": <b>" + messageBody.message + "</b><br/>";
                    convoDiv.append(newMessage);
                    scrollToBottom();
                });

                // Subscribe to my own private channel at /topic/private/<chatId>
                privateSubscription = client.subscribe("/topic/private/" + chatId, function(message) {
                    var messageBody = JSON.parse(message.body);

                    var newMessage = "Private message from " + messageBody.name + ": <b>" + messageBody.message + "</b><br/>";
                    convoDiv.append(newMessage);
                    scrollToBottom();
                });

                // Listen for registration updates
                registrationSubscription = client.subscribe("/topic/registrations", function(message) {
                    var chatters = $("#chatters");

                    // Empty the chatters select field
                    chatters.empty();

                    var obj = JSON.parse(message.body);

                    // Populate the select list with all available chatters
                    $.each(obj.chatters, function(index, value) {
                        var option = $('<option></option>').attr("value", value.chatId).text(value.name);
                        chatters.append(option);
                    });
                });

                // Subscribe to my own private channel for WebRTC messages
                rtcMessageSubscription = client.subscribe("/topic/rtcMessage/" + chatId, function(rawMessage) {
                    var messageBody = JSON.parse(rawMessage.body);

                    switch(messageBody.type) {
                        case "chat-offer":               // A chat offer has been received from some chat participant - prepare to chat!
                            remoteChatter = messageBody.sender;
                            acknowledgeChatInvitation();
                            prepareForVideoChat();
                            startChat();
                            console.log("Remote chatting with " + remoteChatter);
                            break;
                        case "chat-acknowledged":        // You've sent a chat offer and the remote participant has acknowledged - prepare to chat!
                            if( messageBody.sender === remoteChatter ) {
                                console.log("Chat acknowledged by " + remoteChatter);
                                prepareForVideoChat();
                                startChat();
                            } else {
                                console.log("Chat acknowledgement expected by " + remoteChatter + " but received by " + messageBody.sender);
                            }
                            break;
                        case "disconnect-offer":         // You've received a disconnect offer from your chat participant - prepare to disconnect
                            acknowledgeChatHangup();
                            endChat();
                            cleanupAfterVideoChat();
                            remoteChatter = undefined;
                            console.log("Disconnecting from chat with " + messageBody.sender);
                            break;
                        case "disconnect-acknowledged":  // You've sent a disconnect offer to your chat participant and received this acknowledgement - disconnect complete
                            endChat();
                            cleanupAfterVideoChat();
                            console.log("Disconnected from chat with " + messageBody.sender);
                            break;
                        case "offer":                    // Your chat partner has sent you an offer (an RTC Session Description)
                            console.log("offer received from " + remoteChatter);
                            rtcPeerConnection.setRemoteDescription(new RTCSessionDescription(messageBody));
                            doAnswer();
                            break;
                        case "answer":                   // Your chat partner has responded to your offer with an answer (also an RTC Session Description)
                            console.log("answer received from " + remoteChatter);
                            rtcPeerConnection.setRemoteDescription(new RTCSessionDescription(messageBody));
                            break;
                        case "candidate":                // Your chat partner has sent you one of presumably many ICE candidates
                            console.log("ice candidate received from " + remoteChatter);
                            var candidate = new RTCIceCandidate({sdpMLineIndex:messageBody.label, candidate:messageBody.candidate});
                            rtcPeerConnection.addIceCandidate(candidate);
                            break;

                        default:
                            console.log("Unknown message type: ", messageBody.type);
                    }
                });

                startLocalVideo();
            });

            /*************************************************************************************/

            function sendMessage(message){
                console.log('Sending message to ' + remoteChatter + ': ', message);
                client.send("/app/rtcMessage/" + remoteChatter, {}, JSON.stringify(message));
            }

            function sendChatInvitation() {
                var json = {type:'chat-offer', sender:chatId};
                sendMessage(json);
            }

            function acknowledgeChatInvitation() {
                var json = {type:'chat-acknowledged', sender:chatId};
                sendMessage(json);
            }

            function sendChatHangup() {
                var json = {type:'disconnect-offer', sender:chatId};
                sendMessage(json);
            }

            function acknowledgeChatHangup() {
                var json = {type:'disconnect-acknowledged', sender:chatId};
                sendMessage(json);
            }

            function prepareForVideoChat() {
                chatButton.prop('disabled', true);
                hangupButton.prop('disabled', false);
            }

            function cleanupAfterVideoChat() {
                chatButton.prop('disabled', false);
                hangupButton.prop('disabled', true);
                isInitiator = false;
            }

            /*************************************************************************************/

            function handleUserMedia(stream) {
                localStream = stream;

                console.log(stream.getVideoTracks()[0]);

                attachMediaStream(localVideo, stream);
                console.log('Adding local stream.');
            }

            function handleUserMediaError(error){
                console.log('navigator.getUserMedia error: ', error);
            }

            function startLocalVideo() {
                console.log('Getting user media with rtcConstraints', rtcConstraints);
                getUserMedia(rtcConstraints, handleUserMedia, handleUserMediaError);
            }

            function startChat() {
                if (!isStarted && localStream) {
                    createPeerConnection();
                    rtcPeerConnection.addStream(localStream);
                    isStarted = true;
                    if (isInitiator) {
                        doCall();
                    }
                }
            }

            function endChat() {
                if(isStarted) {
                    isStarted = false;
                    rtcPeerConnection.close();
                    rtcPeerConnection = null;
                    remoteStream = null;
                }
            }

            function createPeerConnection() {
                try {
                    rtcPeerConnection = new RTCPeerConnection(rtcConfiguration);
                    rtcPeerConnection.onicecandidate = handleIceCandidate;
                    console.log('Created RTCPeerConnnection');
                } catch (e) {
                    console.log('Failed to create PeerConnection, exception: ' + e.message);
                    alert('Cannot create RTCPeerConnection object.');
                    return;
                }
                rtcPeerConnection.onaddstream = handleRemoteStreamAdded;
                rtcPeerConnection.onremovestream = handleRemoteStreamRemoved;
            }

            function doCall() {
                console.log('Sending offer to peer');
                rtcPeerConnection.createOffer(setLocalAndSendMessage, null);
            }

            function doAnswer() {
                console.log('Sending answer to peer.');
                rtcPeerConnection.createAnswer(setLocalAndSendMessage, null);
            }

            function tryHangup() {
                if(isStarted) {
                    sendChatHangup();
                    remoteChatter = undefined;
                }
            }

            function setLocalAndSendMessage(sessionDescription) {
                rtcPeerConnection.setLocalDescription(sessionDescription);
                sendMessage(sessionDescription)
            }

            function handleRemoteStreamAdded(event) {
                console.log( event.stream ? "Remote stream NOT added" : "Remote stream added" );
                console.log(event);

                attachMediaStream(remoteVideo, event.stream);
                remoteStream = event.stream;
            }
            function handleRemoteStreamRemoved(event) {
                console.log('Remote stream removed. Event: ', event);
            }

            function handleIceCandidate(event) {
                console.log('handleIceCandidate event: ', event);
                if (event.candidate) {
                    var messageMap = {
                        type: 'candidate',
                        label: event.candidate.sdpMLineIndex,
                        id: event.candidate.sdpMid,
                        candidate: event.candidate.candidate
                    };

                    sendMessage(messageMap);
                } else {
                    console.log('End of candidates.');
                }
            }

            /*************************************************************************************/

            chatButton.click(function() {
                var selectedChatterId = $("#chatters").val();

                if(selectedChatterId === chatId) {
                    alert("You can't video chat with yourself, silly!");
                    return;
                }

                remoteChatter = selectedChatterId;
                isInitiator = true;
                sendChatInvitation();
            });

            hangupButton.click(function() {
                tryHangup();
            });

            /*************************************************************************************/

            $("#privateSendButton").click(function() {
                sendPrivateMessage();
            });

            $("#publicSendButton").click(function() {
                sendPublicMessage();
            });

            $("#privatemessage").keyup(function(e) {
                if(enterPressed(e)) {
                    sendPrivateMessage();
                }
            });

            $("#publicmessage").keyup(function(e) {
                if(enterPressed(e)) {
                    sendPublicMessage();
                }
            });

            function enterPressed(e) {
                var code = (e.keyCode ? e.keyCode : e.which);
                return code==13;
            }

            function sendPrivateMessage() {
                var selectedChatterId = $("#chatters").val();
                var privateMessage = $("#privatemessage").val();

                var json = {"senderId": chatId, "message": privateMessage};

                // Send the private message to /app/private/{id}
                client.send("/app/private/" + selectedChatterId, {}, JSON.stringify(json));
            }

            function sendPublicMessage() {
                var publicMessage = $("#publicmessage").val();

                var json = {"senderId": chatId, "message": publicMessage};

                // Send the public message to /app/public
                client.send("/app/public", {}, JSON.stringify(json));
            }

            /*************************************************************************************/

            // Exit neatly on window unload
            $(window).on('beforeunload', function(){
                // Perchance we happen to be in a video chat, hang up.
                tryHangup();

                // Unsubscribe from all channels
                privateSubscription.unsubscribe();
                publicSubscription.unsubscribe();
                registrationSubscription.unsubscribe();
                rtcMessageSubscription.unsubscribe();

                // Tell all chat participants that we're leaving
                var json = {"senderId": chatId, "message": "-- leaving the chat --"};
                client.send("/app/public", {}, JSON.stringify(json));

                // Delete this chatter from the Chatter table
                json = {"chatId": chatId};
                client.send("/app/unregister", {}, JSON.stringify(json));

                // Disconnect the websocket connection
                client.disconnect();
            });

            // ******* debug messages to the console, please ********
            client.debug = function(str) {
                console.log(str);
            };

            // This function will keep the conversationDiv
            // scrolled to the bottom as text is added.
            var scrollToBottom = function() {
                convoDiv.scrollTop(convoDiv[0].scrollHeight);
            };
        });
    </script>
</head>
<body>
    <div class="nav" role="navigation">
        <ul>
            <li><a class="home" href="${createLink(uri: '/')}"><g:message code="default.home.label"/></a></li>
        </ul>
    </div>

    <br/>

    <g:hiddenField name="chatId" value="${chatId}" />
    <g:hiddenField name="name" value="${name}" />

    <div class="boxed">
        <h3>Welcome ${name}!  Your Chat ID is ${chatId}</h3>
    </div>

    <div class="boxed" >
        <label for="privatemessage">Send Private Message</label>
        <input type="text" id= "privatemessage" name="privatemessage">

        <label for="chatters">To</label>
        <select name="chatters" id="chatters"></select>

        <button id="privateSendButton">Send</button>
        <button id="rtcChatButton">Video Chat</button>
        <button id="rtcHangupButton" disabled>Hang Up</button>
    </div>

    <div class="boxed" >
        <label for="publicmessage">Send Public Message</label>
        <input type="text" id="publicmessage" name="publicmessage">

        <button id="publicSendButton">Send</button>
    </div>

    <div class="boxed">
        <div id="conversationDiv"></div>
    </div>

    <div class="boxed" >
        <video id="localVideo" class="videoWindow" autoplay muted></video>
        <video id="remoteVideo" class="videoWindow" autoplay></video>
    </div>

</body>
</html>