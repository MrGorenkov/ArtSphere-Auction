import Vapor
import Fluent

final class CommentModel: Model, Content, @unchecked Sendable {
    static let schema = "comments"

    @ID(key: .id) var id: UUID?
    @Parent(key: "artwork_id") var artwork: ArtworkModel
    @Parent(key: "user_id") var user: UserModel
    @Field(key: "text") var text: String
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(id: UUID? = nil, artworkId: UUID, userId: UUID, text: String) {
        self.id = id
        self.$artwork.id = artworkId
        self.$user.id = userId
        self.text = text
    }
}
