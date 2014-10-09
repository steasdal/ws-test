package ws.test

import groovy.json.JsonSlurper
import org.springframework.messaging.Message
import org.springframework.messaging.handler.annotation.DestinationVariable
import org.springframework.messaging.handler.annotation.MessageMapping
import org.springframework.messaging.simp.SimpMessagingTemplate
import org.springframework.messaging.support.MessageBuilder
import org.springframework.stereotype.Controller

@Controller
class MessagingService {

    ChatterService chatterService
    SimpMessagingTemplate brokerMessagingTemplate

    /**
     * Register a new chat participant.  This'll create a record for the new
     * chatter in the Chatters table.
     *
     * @param registrationMessage a chunk of JSON in the following format:
     *     { name:<chatter name>, chatId:<chatter id> }
     */
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

    /**
     * Unregister an existing chat participant.  This'll delete a chatter's
     * record from the Chatters table.
     *
     * @param unregistrationMessage a chunk of JSON in the following format:
     *     { chatId:<chatter id> }
     */
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

    /**
     * Broadcast a list of all chat participants
     */
    private void updateRegistrations() {
        Collection<Chatter> chatters = chatterService.getAllChatters()

        if(chatters.size() > 0) {
            StringBuffer returnText = new StringBuffer()
            returnText.append( /{ "chatters": [ / )
            returnText.append( chatters.collect{ /{ "name":"${it.name}", "chatId":"${it.chatId}" }/ }.join(",") )
            returnText.append( / ] }/ )

            String destination = "/topic/registrations"
            Message<byte[]> outgoingMessage = MessageBuilder.withPayload(returnText.toString().getBytes()).build()

            brokerMessagingTemplate.send destination, outgoingMessage
        }
    }

    /**
     * Receive a public message and broadcast it to all participants
     * listening on the /public channel
     *
     * @param jsonMessage will be a chunk of JSON in the following format:
     *     { senderId: <sender's chat id>, message: <public chat message> }
     */
    @MessageMapping("/public")
    protected void publicMessage(String jsonMessage) {
        Map messageMap = parseMessageToMap(jsonMessage)
        brokerMessagingTemplate.convertAndSend "/topic/public", messageMap
    }

    /**
     * Receive a private message and forward it on to the intended recipient's
     * private channel.
     *
     * @param chatterId The chat id of the intended recipient of this message
     * @param jsonMessage a chunk of JSON in the following format:
     *     { senderId: <sender's chat id>, message: <private chat message> }
     */
    @MessageMapping("/private/{chatterId}")
    protected void privateMessage(@DestinationVariable String chatterId, String jsonMessage) {
        Map messageMap = parseMessageToMap(jsonMessage)
        brokerMessagingTemplate.convertAndSend "/topic/private/$chatterId".toString(), messageMap
    }

    /**
     * Parse an incoming chat message to get senderId and message, lookup
     * the sender's name in the Chatter table, stuff the sender's name
     * and the chat message into a map and return it.
     *
     * @param jsonMessage An incoming chat message.
     *
     * @return A map containing the sender's name and the chat message.
     */
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

    /**
     * Forward a WebRtc message to a particular chatter
     * @param chatterId The ID of the message's intended recipient
     * @param message The message to forward to the intended recipient
     */
    @MessageMapping("/rtcMessage/{chatterId}")
    protected void rtcMessage(@DestinationVariable String chatterId, Message message) {

        System.out.println("Brokering RTC Message")

        String destination = "/topic/rtcMessage/$chatterId"
        brokerMessagingTemplate.send destination, message
    }
}
