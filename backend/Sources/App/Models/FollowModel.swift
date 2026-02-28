import Vapor
import Fluent

final class FollowModel: Model, Content, @unchecked Sendable {
    static let schema = "follows"

    @ID(key: .id) var id: UUID?
    @Field(key: "follower_id") var followerId: UUID
    @Field(key: "following_id") var followingId: UUID
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(followerId: UUID, followingId: UUID) {
        self.followerId = followerId
        self.followingId = followingId
    }
}
