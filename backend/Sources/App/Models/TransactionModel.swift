import Vapor
import Fluent

final class TransactionModel: Model, Content, @unchecked Sendable {
    static let schema = "transactions"

    @ID(key: .id) var id: UUID?
    @OptionalParent(key: "auction_id") var auction: AuctionModel?
    @Parent(key: "buyer_id") var buyer: UserModel
    @Parent(key: "seller_id") var seller: UserModel
    @Parent(key: "artwork_id") var artwork: ArtworkModel
    @OptionalParent(key: "nft_token_id") var nftToken: NFTTokenModel?
    @Field(key: "amount") var amount: Double
    @Field(key: "status") var status: String
    @OptionalField(key: "tx_hash") var txHash: String?
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        auctionId: UUID? = nil,
        buyerId: UUID,
        sellerId: UUID,
        artworkId: UUID,
        nftTokenId: UUID? = nil,
        amount: Double,
        status: String = "pending",
        txHash: String? = nil
    ) {
        self.id = id
        self.$auction.id = auctionId
        self.$buyer.id = buyerId
        self.$seller.id = sellerId
        self.$artwork.id = artworkId
        self.$nftToken.id = nftTokenId
        self.amount = amount
        self.status = status
        self.txHash = txHash
    }
}

extension TransactionModel {
    func toDTO() -> TransactionDTO {
        TransactionDTO(
            id: self.id?.uuidString ?? "",
            auctionId: self.$auction.id?.uuidString,
            buyerId: self.$buyer.id.uuidString,
            sellerId: self.$seller.id.uuidString,
            artworkId: self.$artwork.id.uuidString,
            amount: self.amount,
            status: self.status,
            txHash: self.txHash,
            createdAt: self.createdAt?.iso8601String ?? ""
        )
    }
}
