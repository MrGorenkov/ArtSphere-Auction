import Vapor
import Fluent

final class Visualization3DModel: Model, Content, @unchecked Sendable {
    static let schema = "visualizations_3d"

    @ID(key: .id) var id: UUID?
    @Parent(key: "artwork_id") var artwork: ArtworkModel
    @Field(key: "file_url") var fileUrl: String
    @OptionalField(key: "file_size_bytes") var fileSizeBytes: Int?
    @Field(key: "format") var format: String
    @OptionalField(key: "normal_map_url") var normalMapUrl: String?
    @OptionalField(key: "thumbnail_url") var thumbnailUrl: String?
    @Timestamp(key: "uploaded_at", on: .create) var uploadedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        artworkId: UUID,
        fileUrl: String,
        fileSizeBytes: Int? = nil,
        format: String = "usdz",
        normalMapUrl: String? = nil,
        thumbnailUrl: String? = nil
    ) {
        self.id = id
        self.$artwork.id = artworkId
        self.fileUrl = fileUrl
        self.fileSizeBytes = fileSizeBytes
        self.format = format
        self.normalMapUrl = normalMapUrl
        self.thumbnailUrl = thumbnailUrl
    }
}

extension Visualization3DModel {
    func toDTO() -> Visualization3DDTO {
        Visualization3DDTO(
            id: self.id?.uuidString ?? "",
            artworkId: self.$artwork.id.uuidString,
            fileUrl: self.fileUrl,
            fileSizeBytes: self.fileSizeBytes,
            format: self.format,
            normalMapUrl: self.normalMapUrl,
            thumbnailUrl: self.thumbnailUrl,
            uploadedAt: self.uploadedAt?.iso8601String ?? ""
        )
    }
}
