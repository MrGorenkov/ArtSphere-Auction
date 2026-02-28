import Foundation

// MARK: - Auth

struct AdminLoginRequest: Codable {
    let walletAddress: String
    let password: String
}

struct AdminLoginResponse: Codable {
    let token: String
    let user: AdminUserBasic
}

struct AdminUserBasic: Codable {
    let id: String
    let username: String
    let displayName: String
    let walletAddress: String
    let bio: String?
    let balance: Double
    let avatarUrl: String?
}

// MARK: - Dashboard

struct DashboardStats: Codable {
    let totalUsers: Int
    let activeUsers: Int
    let totalArtworks: Int
    let publishedArtworks: Int
    let auctionsByStatus: [String: Int]
    let totalBids: Int
    let totalRevenue: Double

    var totalAuctions: Int {
        auctionsByStatus.values.reduce(0, +)
    }

    var activeAuctions: Int {
        auctionsByStatus["active"] ?? 0
    }
}

// MARK: - Users

struct AdminUser: Codable, Identifiable {
    let id: String
    let username: String
    let displayName: String
    let email: String?
    let walletAddress: String
    let avatarUrl: String?
    let bio: String?
    let balance: Double
    let isActive: Bool
    let isAdmin: Bool
    let createdAt: String
    let artworksCount: Int
    let bidsCount: Int
}

// MARK: - Artworks

struct AdminArtwork: Codable, Identifiable {
    let id: String
    let title: String
    let artistName: String
    let description: String
    let imageUrl: String?
    let price: Double?
    let isForSale: Bool
    let isPublished: Bool
    let blockchain: String
    let styleName: String?
    let creatorName: String?
    let auctionsCount: Int
    let createdAt: String
}

struct AdminUpdateArtwork: Codable {
    let title: String?
    let description: String?
    let isPublished: Bool?
    let isForSale: Bool?
}

// MARK: - Auctions

struct AdminAuction: Codable, Identifiable {
    let id: String
    let artworkTitle: String
    let artworkImageUrl: String?
    let startingPrice: Double
    let currentBid: Double
    let reservePrice: Double?
    let bidStep: Double
    let startTime: String
    let endTime: String
    let status: String
    let bidCount: Int
    let creatorName: String?
    let winnerName: String?
    let createdAt: String
}

struct AdminBid: Codable, Identifiable {
    let id: String
    let auctionId: String
    let userId: String
    let userName: String
    let amount: Double
    let timestamp: String
}
