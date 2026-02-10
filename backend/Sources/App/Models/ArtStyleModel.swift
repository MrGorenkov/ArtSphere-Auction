import Vapor
import Fluent

final class ArtStyleModel: Model, Content, @unchecked Sendable {
    static let schema = "art_styles"

    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    @Field(key: "description") var description: String
    @OptionalField(key: "icon_name") var iconName: String?
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    // Relationships
    @Children(for: \.$style) var artworks: [ArtworkModel]

    init() {}

    init(id: UUID? = nil, name: String, description: String = "", iconName: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.iconName = iconName
    }
}

extension ArtStyleModel {
    func toDTO() -> ArtStyleDTO {
        ArtStyleDTO(
            id: self.id?.uuidString ?? "",
            name: self.name,
            description: self.description,
            iconName: self.iconName,
            artworkCount: self.$artworks.value?.count
        )
    }
}
