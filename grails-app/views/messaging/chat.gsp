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

            var privateSubscription;
            var publicSubscription;
            var registrationSubscription;

            client.connect({}, function() {

                // Register the existence of this new chat client with the server
                var json = "{\"name\":\"" + name + "\", \"chatId\":\"" + chatId + "\"}";
                client.send("/app/register", {}, JSON.stringify(json));

                // Subscribe to my own private channel at /topic/private/<chatId>
                privateSubscription = client.subscribe("/topic/private/" + chatId, function(message) {
                    var messageBody = JSON.parse(message.body);

                    var newMessage = "Private message from " + messageBody.name + ": <b>" + messageBody.message + "</b><br/>";
                    $("#conversationDiv").append(newMessage);
                    scrollToBottom();
                });

                // Subscribe to the public channel at /topic/public
                publicSubscription = client.subscribe("/topic/public", function(message) {
                    var messageBody = JSON.parse(message.body);

                    var newMessage = "Public message from " + messageBody.name + ": <b>" + messageBody.message + "</b><br/>";
                    $("#conversationDiv").append(newMessage);
                    scrollToBottom();
                });

                // Listen for registration updates
                registrationSubscription = client.subscribe("/topic/registrations", function(message) {
                    // Empty the chatters select field
                    $("#chatters").empty();

                    // TODO: Figure out why this is double encoded.
                    var obj = $.parseJSON( $.parseJSON(message.body) );

                    // Populate the select list with all available chatters
                    $.each(obj.chatters, function(index, value) {
                        var option = $('<option></option>').attr("value", value.chatId).text(value.name);
                        $("#chatters").append(option);
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
            }

            // This function will keep the conversationDiv
            // scrolled to the bottom as text is added.
            var scrollToBottom = function() {
                var convoDiv = $("#conversationDiv");
                convoDiv.scrollTop(convoDiv[0].scrollHeight);
            }
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
        <h3>Welcome ${name}</h3>
    </div>

    <div class="boxed" >
        <label for="privatemessage">Send Private Message</label>
        <input type="text" id= "privatemessage" name="privatemessage">

        <label for="chatters">To</label>
        <select name="chatters" id="chatters"></select>

        <button id="privateSendButton">Send</button>
    </div>

    <div class="boxed" >
        <label for="publicmessage">Send Public Message</label>
        <input type="text" id="publicmessage" name="publicmessage">

        <button id="publicSendButton">Send</button>
    </div>

    <div class="boxed">
        <div id="conversationDiv"></div>
    </div>


</body>
</html>