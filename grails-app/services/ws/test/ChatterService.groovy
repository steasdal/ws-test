package ws.test

import grails.transaction.Transactional
import org.apache.commons.lang.Validate

@Transactional
class ChatterService {

    def newChatter(String name, String chatId) {
        Validate.notNull(name, "name cannot be null")
        Validate.notNull(chatId, "id cannot be null")

        Chatter newChatter = new Chatter(
                name: name,
                chatId: chatId
        ).save(flush:true)

        return newChatter
    }

    def deleteChatter(String chatId) {
        Validate.notNull(chatId, "id cannot be null")

        Chatter chatter = Chatter.findByChatId(chatId)
        chatter.delete()
    }

    Collection<Chatter> getAllChatters() {
        return Chatter.findAll()
    }
}
