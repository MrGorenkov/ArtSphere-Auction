import Vapor
import Fluent

final class MessageModel: Model, Content {
    static let schema = "messages"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "sender_id")
    var senderId: UUID

    @Field(key: "receiver_id")
    var receiverId: UUID

    @OptionalField(key: "artwork_id")
    var artworkId: UUID?

    @Field(key: "text")
    var text: String

    @Field(key: "is_read")
    var isRead: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(senderId: UUID, receiverId: UUID, artworkId: UUID? = nil, text: String) {
        self.senderId = senderId
        self.receiverId = receiverId
        self.artworkId = artworkId
        self.text = text
        self.isRead = false
    }
}
