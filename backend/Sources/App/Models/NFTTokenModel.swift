import Vapor
import Fluent

final class NFTTokenModel: Model, Content, @unchecked Sendable {
    static let schema = "nft_tokens"

    @ID(key: .id) var id: UUID?
    @Parent(key: "artwork_id") var artwork: ArtworkModel
    @Parent(key: "owner_id") var owner: UserModel
    @Field(key: "contract_address") var contractAddress: String
    @OptionalField(key: "token_id_on_chain") var tokenIdOnChain: String?
    @Field(key: "blockchain") var blockchain: String
    @Field(key: "status") var status: String
    @Timestamp(key: "minted_at", on: .create) var mintedAt: Date?
    @OptionalField(key: "metadata_uri") var metadataUri: String?

    init() {}

    init(
        id: UUID? = nil,
        artworkId: UUID,
        ownerId: UUID,
        contractAddress: String,
        tokenIdOnChain: String? = nil,
        blockchain: String = "Polygon",
        status: String = "minted",
        metadataUri: String? = nil
    ) {
        self.id = id
        self.$artwork.id = artworkId
        self.$owner.id = ownerId
        self.contractAddress = contractAddress
        self.tokenIdOnChain = tokenIdOnChain
        self.blockchain = blockchain
        self.status = status
        self.metadataUri = metadataUri
    }
}

extension NFTTokenModel {
    func toDTO() -> NFTTokenDTO {
        NFTTokenDTO(
            id: self.id?.uuidString ?? "",
            artworkId: self.$artwork.id.uuidString,
            ownerId: self.$owner.id.uuidString,
            contractAddress: self.contractAddress,
            tokenIdOnChain: self.tokenIdOnChain,
            blockchain: self.blockchain,
            status: self.status,
            mintedAt: self.mintedAt?.iso8601String ?? "",
            metadataUri: self.metadataUri
        )
    }
}
