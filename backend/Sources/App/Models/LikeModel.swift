import Vapor
import Fluent

final class LikeModel: Model, Content, @unchecked Sendable {
    static let schema = "likes"

    @ID(key: .id) var id: UUID?
    @Field(key: "user_id") var userId: UUID
    @Field(key: "artwork_id") var artworkId: UUID
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(userId: UUID, artworkId: UUID) {
        self.userId = userId
        self.artworkId = artworkId
    }
}
