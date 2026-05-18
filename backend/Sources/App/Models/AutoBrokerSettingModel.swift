import Fluent
import Vapor

final class AutoBrokerSettingModel: Model, Content {
    static let schema = "auto_broker_settings"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: UserModel

    @Parent(key: "auction_id")
    var auction: AuctionModel

    @Field(key: "max_amount")
    var maxAmount: Double

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() { }

    init(id: UUID? = nil, userId: UUID, auctionId: UUID, maxAmount: Double) {
        self.id = id
        self.$user.id = userId
        self.$auction.id = auctionId
        self.maxAmount = maxAmount
    }
}