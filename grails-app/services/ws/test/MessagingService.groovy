package ws.test

import groovy.json.JsonSlurper
import org.springframework.messaging.handler.annotation.DestinationVariable
import org.springframework.messaging.handler.annotation.MessageMapping
import org.springframework.stereotype.Controller

@Controller
class MessagingService {

    ChatterService chatterService
    def brokerMessagingTemplate

    @MessageMapping("/register")
    protected void register(String registrationMessage) {

        JsonSlurper slurper = new JsonSlurper()
        def json = slurper.parseText(registrationMessage)

        def name = json.name
        def chatId = json.chatId

        try {
            Chatter chatter = chatterService.newChatter(name, chatId)
        } catch (Exception exception) {
            System.out.println exception.getMessage()
        }

        updateRegistrations()
    }

    @MessageMapping("/unregister")
    protected void unregister(String unregistrationMessage) {

        JsonSlurper slurper = new JsonSlurper()
        def json = slurper.parseText(unregistrationMessage)

        def chatId = json.chatId

        try {
            chatterService.deleteChatter(chatId)
        } catch (Exception exception) {
            System.out.println exception.getMessage()
        }

        updateRegistrations()
    }

    private void updateRegistrations() {
        Collection<Chatter> chatters = chatterService.getAllChatters()

        if(chatters.size() > 0) {
            StringBuffer returnText = new StringBuffer()
            returnText.append( /{ "chatters": [ / )
            returnText.append( chatters.collect{ /{ "name":"${it.name}", "chatId":"${it.chatId}" }/ }.join(",") )
            returnText.append( / ] }/ )

            brokerMessagingTemplate.convertAndSend "/topic/registrations", returnText.toString()
        }
    }

    @MessageMapping("/public")
    protected String publicMessage(String jsonMessage) {
        Map messageMap = parseMessageToMap(jsonMessage)
        brokerMessagingTemplate.convertAndSend "/topic/public", messageMap
    }

    @MessageMapping("/private/{chatterId}")
    protected void privateMessage(@DestinationVariable String chatterId, String jsonMessage) {
        Map messageMap = parseMessageToMap(jsonMessage)
        brokerMessagingTemplate.convertAndSend "/topic/private/$chatterId".toString(), messageMap
    }

    // The incoming jsonMessage will be a chunk of JSON with two fields: senderId and message.
    // The senderId will be a UUID representing the chat participant that sent the message
    // while the message will be the actual message string being sent.  It might look a little
    // something like this:
    //
    // { "senderId": "1276f4bc-a625-47cf-8aa5-3c6595ca4dea", "message": "Hey, how you doin?" }
    //
    private static Map parseMessageToMap(String jsonMessage) {
        JsonSlurper slurper = new JsonSlurper()
        def json = slurper.parseText(jsonMessage)

        def senderId = json.senderId
        def message = json.message

        // Look up the name of the sender in the Chatter table
        def senderName = Chatter.findByChatId(senderId)?.name

        // Wrangle the sender name and message into a map
        return [name: senderName, message: message]
    }
}
