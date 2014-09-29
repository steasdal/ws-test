package ws.test

class MessagingController {
    def index() {
        String sessionId = UUID.randomUUID().toString()
        [sessionId:sessionId]
    }

    def chat() {
        [sessionId:params.sessionId, name:params.name]
    }
}
