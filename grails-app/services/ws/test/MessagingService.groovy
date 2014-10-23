package ws.test

import org.springframework.messaging.Message
import org.springframework.messaging.handler.annotation.DestinationVariable
import org.springframework.messaging.handler.annotation.MessageMapping
import org.springframework.messaging.simp.SimpMessagingTemplate
import org.springframework.stereotype.Controller

@Controller
class MessagingService {

    ChatterService chatterService
    SimpMessagingTemplate brokerMessagingTemplate

    /**
     * Register a new chat participant.  This'll create a record for the new
     * chatter in the Chatters table.
     *
     * @param registrationMessage a RegistrationMessage
     */
    @MessageMapping("/register")
    protected void register(RegistrationMessage registrationMessage) {
        try {
            Chatter chatter = chatterService.newChatter(registrationMessage.name, registrationMessage.chatId)
        } catch (Exception exception) {
            System.out.println exception.getMessage()
        }

        updateRegistrations()
    }

    /**
     * Unregister an existing chat participant.  This'll delete a chatter's
     * record from the Chatters table.
     *
     * @param unregistrationMessage a RegistrationMessage
     */
    @MessageMapping("/unregister")
    protected void unregister(RegistrationMessage unregistrationMessage) {
        try {
            chatterService.deleteChatter(unregistrationMessage.chatId)
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
            def payload = [
                chatters: chatters.collect { [name: it.name, chatId: it.chatId] }
            ]
            String destination = "/topic/registrations"

            brokerMessagingTemplate.convertAndSend destination, payload
        }
    }

    /**
     * Receive a public message and broadcast it to all participants
     * listening on the /public channel
     *
     * @param chatMessage a ChatMessage
     */
    @MessageMapping("/public")
    protected void publicMessage(ChatMessage chatMessage) {
        Map messageMap = parseMessageToMap(chatMessage)
        brokerMessagingTemplate.convertAndSend "/topic/public", messageMap
    }

    /**
     * Receive a private message and forward it on to the intended recipient's
     * private channel.
     *
     * @param chatterId The chat id of the intended recipient of this message
     * @param chatMessage a ChatMessage
     */
    @MessageMapping("/private/{chatterId}")
    protected void privateMessage(@DestinationVariable String chatterId, ChatMessage chatMessage) {
        Map messageMap = parseMessageToMap(chatMessage)
        brokerMessagingTemplate.convertAndSend "/topic/private/$chatterId".toString(), messageMap
    }

    /**
     * Parse an incoming chat message to get senderId and message, lookup
     * the sender's name in the Chatter table, stuff the sender's name
     * and the chat message into a map and return it.
     *
     * @param chatMessage An incoming chat message.
     *
     * @return A map containing the sender's name and the chat message.
     */
    private static Map parseMessageToMap(ChatMessage chatMessage) {
        // Look up the name of the sender in the Chatter table
        def senderName = Chatter.findByChatId(chatMessage.senderId)?.name

        // Wrangle the sender name and message into a map
        return [name: senderName, message: chatMessage.message]
    }

    /**
     * Forward a WebRtc message to a particular chatter.
     * @param chatterId The ID of the message's intended recipient
     * @param message The message to forward to the intended recipient
     */
    @MessageMapping("/rtcMessage/{chatterId}")
    protected void rtcMessage(@DestinationVariable String chatterId, Message message) {
        String destination = "/topic/rtcMessage/$chatterId"
        brokerMessagingTemplate.send destination, message
    }
}
