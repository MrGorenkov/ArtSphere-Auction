import Foundation
import SwiftUI

struct NFTArtwork: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var artistName: String
    var description: String
    var imageName: String
    var category: ArtworkCategory
    let createdAt: Date

    // Blockchain metadata
    var tokenId: String?
    var contractAddress: String?
    var blockchain: BlockchainNetwork

    // Image source
    var imageSource: ImageSource
    var localImageData: Data?
    var imageURL: String?
    var modelUrl: String?

    // Texture analysis
    var textureComplexityScore: Double?

    init(
        id: UUID = UUID(),
        title: String,
        artistName: String,
        description: String,
        imageName: String,
        category: ArtworkCategory,
        createdAt: Date = Date(),
        tokenId: String? = nil,
        contractAddress: String? = nil,
        blockchain: BlockchainNetwork = .ethereum,
        imageSource: ImageSource = .procedural,
        localImageData: Data? = nil,
        imageURL: String? = nil,
        modelUrl: String? = nil,
        textureComplexityScore: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.artistName = artistName
        self.description = description
        self.imageName = imageName
        self.category = category
        self.createdAt = createdAt
        self.tokenId = tokenId
        self.contractAddress = contractAddress
        self.blockchain = blockchain
        self.imageSource = imageSource
        self.localImageData = localImageData
        self.imageURL = imageURL
        self.modelUrl = modelUrl
        self.textureComplexityScore = textureComplexityScore
    }

    enum ImageSource: String, Codable, Hashable {
        case procedural
        case uploaded
        case url
        case bundled
    }

    enum ArtworkCategory: String, CaseIterable, Identifiable, Codable {
        case digitalPainting = "Digital Painting"
        case generativeArt = "Generative Art"
        case photography = "Photography"
        case abstract = "Abstract"
        case pixel = "Pixel Art"
        case threeD = "3D Art"

        var id: String { rawValue }

        var iconName: String {
            switch self {
            case .digitalPainting: return "paintbrush.fill"
            case .generativeArt: return "wand.and.stars"
            case .photography: return "camera.fill"
            case .abstract: return "circle.hexagongrid.fill"
            case .pixel: return "square.grid.3x3.fill"
            case .threeD: return "cube.fill"
            }
        }
    }

    /// Whether this artwork can be viewed in AR (has a 3D model or can generate one from image).
    var isARAvailable: Bool {
        if modelUrl != nil { return true }
        switch imageSource {
        case .uploaded: return localImageData != nil
        case .url: return imageURL != nil
        case .procedural, .bundled: return true
        }
    }

    enum BlockchainNetwork: String, CaseIterable, Codable {
        case ethereum = "Ethereum"
        case polygon = "Polygon"
    }
}
