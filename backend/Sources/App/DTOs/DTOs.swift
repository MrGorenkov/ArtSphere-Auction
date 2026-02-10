import Vapor

// MARK: - Response DTOs

struct UserDTO: Content {
    let id: String
    let username: String
    let displayName: String
    let walletAddress: String
    let bio: String?
    let balance: Double
    let avatarUrl: String?
}

struct ArtworkDTO: Content {
    let id: String
    let title: String
    let artistName: String
    let description: String
    let imageUrl: String?
    let filePath: String?
    let price: Double?
    let isForSale: Bool
    let styleId: String?
    let styleName: String?
    let blockchain: String
    let createdAt: String
}

struct AuctionDTO: Content {
    let id: String
    let artworkId: String
    let startTime: String
    let endTime: String
    let currentBid: Double
    let startingPrice: Double
    let reservePrice: Double?
    let bidStep: Double
    let status: String
    let winnerId: String?
    let creatorId: String?
    let bidCount: Int
}

struct AuctionDetailDTO: Content {
    let auction: AuctionDTO
    let artwork: ArtworkDTO
    let bids: [BidDTO]
}

struct BidDTO: Content {
    let id: String
    let auctionId: String
    let userId: String
    let userName: String
    let amount: Double
    let timestamp: String
}

struct CollectionDTO: Content {
    let id: String
    let name: String
    let description: String?
    let artworkIds: [String]
    let userId: String
    let isPrivate: Bool
    let isDefault: Bool
    let createdAt: String
    let updatedAt: String
}

struct ArtStyleDTO: Content {
    let id: String
    let name: String
    let description: String
    let iconName: String?
    let artworkCount: Int?
}

struct Visualization3DDTO: Content {
    let id: String
    let artworkId: String
    let fileUrl: String
    let fileSizeBytes: Int?
    let format: String
    let normalMapUrl: String?
    let thumbnailUrl: String?
    let uploadedAt: String
}

struct NFTTokenDTO: Content {
    let id: String
    let artworkId: String
    let ownerId: String
    let contractAddress: String
    let tokenIdOnChain: String?
    let blockchain: String
    let status: String
    let mintedAt: String
    let metadataUri: String?
}

struct TransactionDTO: Content {
    let id: String
    let auctionId: String?
    let buyerId: String
    let sellerId: String
    let artworkId: String
    let amount: Double
    let status: String
    let txHash: String?
    let createdAt: String
}

// MARK: - Request DTOs

struct LoginRequest: Content {
    let walletAddress: String
    let password: String
}

struct RegisterRequest: Content, Validatable {
    let username: String
    let displayName: String
    let walletAddress: String
    let password: String
    let email: String?

    static func validations(_ validations: inout Validations) {
        validations.add("username", as: String.self, is: .count(3...50))
        validations.add("displayName", as: String.self, is: .count(1...100))
        validations.add("walletAddress", as: String.self, is: .count(3...100))
        validations.add("password", as: String.self, is: .count(6...))
    }
}

struct LoginResponse: Content {
    let token: String
    let user: UserDTO
}

struct PlaceBidRequest: Content, Validatable {
    let auctionId: String
    let amount: Double

    static func validations(_ validations: inout Validations) {
        validations.add("amount", as: Double.self, is: .range(0.001...))
    }
}

struct CreateAuctionRequest: Content, Validatable {
    let artworkId: String
    let startingPrice: Double
    let reservePrice: Double?
    let bidStep: Double?
    let durationHours: Int

    static func validations(_ validations: inout Validations) {
        validations.add("startingPrice", as: Double.self, is: .range(0.001...))
        validations.add("durationHours", as: Int.self, is: .range(1...168))
    }
}

struct CreateArtworkRequest: Content {
    let title: String
    let description: String?
    let styleId: String?
    let price: Double?
    let blockchain: String?
}

struct CreateCollectionRequest: Content {
    let name: String
    let description: String?
    let isPrivate: Bool?
}

struct UpdateCollectionRequest: Content {
    let name: String?
    let description: String?
    let isPrivate: Bool?
}

struct CollectionArtworkRequest: Content {
    let artworkId: String
    let position: Int?
    let userNote: String?
}

struct MintNFTRequest: Content {
    let artworkId: String
    let blockchain: String?
}

// MARK: - WebSocket Messages

struct WSBidMessage: Codable {
    let type: String  // "new_bid"
    let auctionId: String
    let bid: BidDTO
    let currentBid: Double
    let bidCount: Int
}

struct WSAuctionUpdate: Codable {
    let type: String  // "auction_update"
    let auctionId: String
    let status: String
    let winnerId: String?
}

// MARK: - API Response Wrapper

struct APIResponse<T: Content>: Content {
    let success: Bool
    let data: T?
    let message: String?

    init(data: T) {
        self.success = true
        self.data = data
        self.message = nil
    }

    init(error message: String) {
        self.success = false
        self.data = nil
        self.message = message
    }
}
