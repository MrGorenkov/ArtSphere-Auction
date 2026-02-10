import Foundation

struct NFTCollection: Identifiable, Hashable {
    let id: UUID
    var name: String
    var description: String
    var artworkIds: [UUID]
    var coverImageArtworkId: UUID?
    let createdAt: Date
    var updatedAt: Date
    var isDefault: Bool

    init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        artworkIds: [UUID] = [],
        coverImageArtworkId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.artworkIds = artworkIds
        self.coverImageArtworkId = coverImageArtworkId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDefault = isDefault
    }

    var artworkCount: Int {
        artworkIds.count
    }
}
