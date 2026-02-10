import Vapor
import Fluent

final class AuctionModel: Model, Content, @unchecked Sendable {
    static let schema = "auctions"

    @ID(key: .id) var id: UUID?
    @Parent(key: "artwork_id") var artwork: ArtworkModel
    @OptionalParent(key: "creator_id") var creator: UserModel?
    @Field(key: "starting_price") var startingPrice: Double
    @Field(key: "current_bid") var currentBid: Double
    @OptionalField(key: "reserve_price") var reservePrice: Double?
    @Field(key: "bid_step") var bidStep: Double
    @Field(key: "start_time") var startTime: Date
    @Field(key: "end_time") var endTime: Date
    @Field(key: "status") var status: String
    @OptionalField(key: "winner_id") var winnerId: UUID?
    @Field(key: "bid_count") var bidCount: Int
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

    // Relationships
    @Children(for: \.$auction) var bids: [BidModel]

    init() {}

    init(
        id: UUID? = nil,
        artworkId: UUID,
        creatorId: UUID? = nil,
        startingPrice: Double,
        reservePrice: Double? = nil,
        bidStep: Double = 0.01,
        startTime: Date = Date(),
        endTime: Date,
        status: String = "active"
    ) {
        self.id = id
        self.$artwork.id = artworkId
        self.$creator.id = creatorId
        self.startingPrice = startingPrice
        self.currentBid = 0
        self.reservePrice = reservePrice
        self.bidStep = bidStep
        self.startTime = startTime
        self.endTime = endTime
        self.status = status
        self.bidCount = 0
    }
}

extension AuctionModel {
    func toDTO() -> AuctionDTO {
        AuctionDTO(
            id: self.id?.uuidString ?? "",
            artworkId: self.$artwork.id.uuidString,
            startTime: self.startTime.iso8601String,
            endTime: self.endTime.iso8601String,
            currentBid: self.currentBid,
            startingPrice: self.startingPrice,
            reservePrice: self.reservePrice,
            bidStep: self.bidStep,
            status: self.status,
            winnerId: self.winnerId?.uuidString,
            creatorId: self.$creator.id?.uuidString,
            bidCount: self.bidCount
        )
    }
}
