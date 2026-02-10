import Vapor
import Fluent

final class ArtworkModel: Model, Content, @unchecked Sendable {
    static let schema = "artworks"

    @ID(key: .id) var id: UUID?
    @Field(key: "title") var title: String
    @Field(key: "artist_name") var artistName: String
    @Field(key: "description") var description: String
    @OptionalField(key: "image_url") var imageUrl: String?
    @OptionalField(key: "file_path") var filePath: String?
    @OptionalField(key: "price") var price: Double?
    @Field(key: "is_for_sale") var isForSale: Bool
    @OptionalParent(key: "style_id") var style: ArtStyleModel?
    @Field(key: "blockchain") var blockchain: String
    @OptionalField(key: "metadata_json") var metadataJson: String?
    @OptionalParent(key: "creator_id") var creator: UserModel?
    @Field(key: "is_published") var isPublished: Bool
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

    // Relationships
    @Children(for: \.$artwork) var visualizations: [Visualization3DModel]
    @Children(for: \.$artwork) var nftTokens: [NFTTokenModel]

    init() {}

    init(
        id: UUID? = nil,
        title: String,
        artistName: String,
        description: String = "",
        imageUrl: String? = nil,
        filePath: String? = nil,
        price: Double? = nil,
        isForSale: Bool = true,
        styleId: UUID? = nil,
        blockchain: String = "Polygon",
        creatorId: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.artistName = artistName
        self.description = description
        self.imageUrl = imageUrl
        self.filePath = filePath
        self.price = price
        self.isForSale = isForSale
        self.$style.id = styleId
        self.blockchain = blockchain
        self.$creator.id = creatorId
        self.isPublished = true
    }
}

extension ArtworkModel {
    func toDTO() -> ArtworkDTO {
        ArtworkDTO(
            id: self.id?.uuidString ?? "",
            title: self.title,
            artistName: self.artistName,
            description: self.description,
            imageUrl: self.imageUrl,
            filePath: self.filePath,
            price: self.price,
            isForSale: self.isForSale,
            styleId: self.$style.id?.uuidString,
            styleName: self.$style.wrappedValue?.name,
            blockchain: self.blockchain,
            createdAt: self.createdAt?.iso8601String ?? ""
        )
    }
}

extension Date {
    var iso8601String: String {
        ISO8601DateFormatter().string(from: self)
    }
}
