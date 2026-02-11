import Vapor
import Fluent

final class BidModel: Model, Content, @unchecked Sendable {
    static let schema = "bids"

    @ID(key: .id) var id: UUID?
    @Parent(key: "auction_id") var auction: AuctionModel
    @Parent(key: "user_id") var user: UserModel
    @Field(key: "amount") var amount: Double
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Field(key: "synced") var synced: Bool

    init() {}

    init(id: UUID? = nil, auctionId: UUID, userId: UUID, amount: Double, synced: Bool = false) {
        self.id = id
        self.$auction.id = auctionId
        self.$user.id = userId
        self.amount = amount
        self.synced = synced
    }
}

extension BidModel {
    func toDTO(userName: String) -> BidDTO {
        BidDTO(
            id: self.id?.uuidString ?? "",
            auctionId: self.$auction.id.uuidString,
            userId: self.$user.id.uuidString,
            userName: userName,
            amount: self.amount,
            timestamp: self.createdAt?.iso8601String ?? ""
        )
    }
}
