package ws.test

class MessagingController {
    def index() {
        String chatId = UUID.randomUUID().toString()
        [chatId:chatId]
    }

    def chat() {
        [chatId:params.chatId, name:params.name]
    }
}
