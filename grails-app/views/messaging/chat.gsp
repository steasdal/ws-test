<!DOCTYPE html>

<html>
<head>
    <meta name="layout" content="main"/>

    <asset:javascript src="jquery" />
    <asset:javascript src="spring-websocket" />
    <asset:stylesheet href="chat.css"/>

    <script type="text/javascript">
        $(function() {
            var chatId = $("#chatId").val();
            var name = $("#name").val();

            var socket = new SockJS("${createLink(uri: '/stomp')}");
            var client = Stomp.over(socket);

            var privateSubscription, publicSubscription, registrationSubscription;

            var localVideo = $("#localVideo")[0];
            var remoteVideo = $("remoteVideo")[0];

            var chatButton = $("#rtcChatButton");
            var hangupButton = $("#rtcHangupButton");

            var localStream, remoteStream, rtcPeerConnection;
            var rtcSessionDescriptionSubscription, rtcIceCandidateSubscription;

            client.connect({}, function() {

                // Register the existence of this new chat client with the server
                var json = "{\"name\":\"" + name + "\", \"chatId\":\"" + chatId + "\"}";
                client.send("/app/register", {}, JSON.stringify(json));

                // Subscribe to the public channel at /topic/public
                publicSubscription = client.subscribe("/topic/public", function(message) {
                    var messageBody = JSON.parse(message.body);

                    var newMessage = "Public message from " + messageBody.name + ": <b>" + messageBody.message + "</b><br/>";
                    $("#conversationDiv").append(newMessage);
                    scrollToBottom();
                });

                // Subscribe to my own private channel at /topic/private/<chatId>
                privateSubscription = client.subscribe("/topic/private/" + chatId, function(message) {
                    var messageBody = JSON.parse(message.body);

                    var newMessage = "Private message from " + messageBody.name + ": <b>" + messageBody.message + "</b><br/>";
                    $("#conversationDiv").append(newMessage);
                    scrollToBottom();
                });

                rtcSessionDescriptionSubscription = client.subscribe("/topic/rtcSessionDescription/" + chatId, function(message) {
                    var messageBody = JSON.parse(message.body);

                    console.log("Session Description Received!");
                    console.log(messageBody);

                    var sdp = messageBody.sdp;
                    var senderId = messageBody.senderId;

                    if(!rtcPeerConnection) {
                        startRtc(false, senderId);
                    }

                    rtcPeerConnection.setRemoteDescription(new RTCSessionDescription(sdp));
                });

                rtcIceCandidateSubscription = client.subscribe("/topic/rtcIceCandidate/" + chatId, function(message) {
                    var messageBody = JSON.parse(message.body);

                    console.log("ICE Candidate Received!");
                    console.log(messageBody);

                    var candidate = messageBody.candidate;
                    var senderId = messageBody.senderId;

                    if(!rtcPeerConnection) {
                        startRtc(false, senderId);
                    }

                    rtcPeerConnection.addIceCandidate(new RTCIceCandidate(candidate));
                });

                // Listen for registration updates
                registrationSubscription = client.subscribe("/topic/registrations", function(message) {
                    var chatters = $("#chatters");

                    // Empty the chatters select field
                    chatters.empty();

                    // TODO: Figure out why this is double encoded.
                    var obj = $.parseJSON( $.parseJSON(message.body) );

                    // Populate the select list with all available chatters
                    $.each(obj.chatters, function(index, value) {
                        var option = $('<option></option>').attr("value", value.chatId).text(value.name);
                        chatters.append(option);
                    });
                });
            });

            $("#privateSendButton").click(function() {
                var selectedChatterId = $("#chatters").val();
                var privateMessage = $("#privatemessage").val();

                var json = "{ \"senderId\": \"" + chatId +  "\", \"message\": \"" + privateMessage + "\" }";

                // Send the private message to /app/private/{id}
                client.send("/app/private/" + selectedChatterId, {}, JSON.stringify(json));
            });

            $("#publicSendButton").click(function() {
                var publicMessage = $("#publicmessage").val();

                var json = "{ \"senderId\": \"" + chatId +  "\", \"message\": \"" + publicMessage + "\" }";

                // Send the public message to /app/public
                client.send("/app/public", {}, JSON.stringify(json));
            });

            // Exit neatly on window unload
            $(window).on('beforeunload', function(){
                privateSubscription.unsubscribe();
                publicSubscription.unsubscribe();
                registrationSubscription.unsubscribe();

                // Tell all chat participants that we're leaving
                var json = "{ \"senderId\": \"" + chatId +  "\", \"message\": \"-- leaving the chat --\" }";
                client.send("/app/public", {}, JSON.stringify(json));

                // Delete this chatter from the Chatter table
                json = "{ \"chatId\": \"" + chatId + "\" }";
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
                var convoDiv = $("#conversationDiv");
                convoDiv.scrollTop(convoDiv[0].scrollHeight);
            };















            chatButton.click(function() {
                var selectedChatterId = $("#chatters").val();

                if(selectedChatterId === chatId) {
                    alert("You can't video chat with yourself, silly!");
                    return;
                }

                startRtc(true, selectedChatterId);

                chatButton.prop('disabled', true);
                hangupButton.prop('disabled', false);


            });

            var startRtc = function(isCaller, targetChatter) {

                rtcPeerConnection = new webkitRTCPeerConnection(null);

                rtcPeerConnection.onicecandidate = function(evt) {
                    client.send("/rtcIceCandidate/" + targetChatter, {}, JSON.stringify({ "candidate": evt.candidate, "senderId": chatId }));
                };

                rtcPeerConnection.onaddstream = function(evt) {
                    remoteVideo.src = URL.createObjectUrl(evt.stream);
                    remoteStream = evt.stream;
                };

                navigator.getUserMedia =
                        navigator.getUserMedia ||
                        navigator.webkitGetUserMedia ||
                        navigator.mozGetUserMedia;

                navigator.getUserMedia(
                        {audio:true, video:true},

                        function(stream) {
                            localVideo.src = URL.createObjectURL(stream);
                            rtcPeerConnection.addStream(stream);
                            localStream = stream;

                            if(isCaller) {
                                rtcPeerConnection.createOffer(gotDescription);
                            } else {
                                rtcPeerConnection.createAnswer(rtcPeerConnection.remoteDescription, gotDescription);
                            }

                            function gotDescription(desc) {
                                rtcPeerConnection.setLocalDescription(desc);
                                client.send("/rtcSessionDescription/" + targetChatter, {}, JSON.stringify({ "sdp": desc, "senderId": chatId }));
                            }
                        },

                        function(error) {
                            trace("navigator.getUserMedia error: ", error);
                        }
                );
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
        <video id="localVideo" class="videoWindow" autoplay></video>
        <video id="remoteVideo" class="videoWindow" autoplay></video>
    </div>

</body>
</html>