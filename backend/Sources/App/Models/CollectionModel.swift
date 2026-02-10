import Vapor
import Fluent

final class CollectionModel: Model, Content, @unchecked Sendable {
    static let schema = "collections"

    @ID(key: .id) var id: UUID?
    @Parent(key: "user_id") var user: UserModel
    @Field(key: "name") var name: String
    @Field(key: "description") var description: String
    @OptionalField(key: "cover_artwork_id") var coverArtworkId: UUID?
    @Field(key: "is_private") var isPrivate: Bool
    @Field(key: "is_default") var isDefault: Bool
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

    // Many-to-many via pivot
    @Siblings(through: CollectionArtworkPivot.self, from: \.$collection, to: \.$artwork)
    var artworks: [ArtworkModel]

    init() {}

    init(id: UUID? = nil, userId: UUID, name: String, description: String = "", isPrivate: Bool = false, isDefault: Bool = false) {
        self.id = id
        self.$user.id = userId
        self.name = name
        self.description = description
        self.isPrivate = isPrivate
        self.isDefault = isDefault
    }
}

// Pivot table for collection <-> artwork
final class CollectionArtworkPivot: Model, @unchecked Sendable {
    static let schema = "collection_artworks"

    @ID(key: .id) var id: UUID?
    @Parent(key: "collection_id") var collection: CollectionModel
    @Parent(key: "artwork_id") var artwork: ArtworkModel
    @Field(key: "position") var position: Int
    @Field(key: "user_note") var userNote: String
    @Timestamp(key: "added_at", on: .create) var addedAt: Date?

    init() {}

    init(collectionId: UUID, artworkId: UUID, position: Int = 0, userNote: String = "") {
        self.$collection.id = collectionId
        self.$artwork.id = artworkId
        self.position = position
        self.userNote = userNote
    }
}

extension CollectionModel {
    func toDTO(artworkIds: [String] = []) -> CollectionDTO {
        CollectionDTO(
            id: self.id?.uuidString ?? "",
            name: self.name,
            description: self.description,
            artworkIds: artworkIds,
            userId: self.$user.id.uuidString,
            isPrivate: self.isPrivate,
            isDefault: self.isDefault,
            createdAt: self.createdAt?.iso8601String ?? "",
            updatedAt: self.updatedAt?.iso8601String ?? ""
        )
    }
}
