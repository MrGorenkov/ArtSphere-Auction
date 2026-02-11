import Foundation

struct User: Identifiable, Hashable {
    let id: UUID
    var username: String
    var displayName: String
    var walletAddress: String
    var avatarName: String?
    var avatarUrl: String?
    var bio: String
    var ownedArtworks: [UUID]
    var favoritedArtworks: [UUID]
    var collections: [NFTCollection]
    var balance: Double

    init(
        id: UUID = UUID(),
        username: String,
        displayName: String,
        walletAddress: String,
        avatarName: String? = nil,
        avatarUrl: String? = nil,
        bio: String = "",
        ownedArtworks: [UUID] = [],
        favoritedArtworks: [UUID] = [],
        collections: [NFTCollection] = [],
        balance: Double = 25.0
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.walletAddress = walletAddress
        self.avatarName = avatarName
        self.avatarUrl = avatarUrl
        self.bio = bio
        self.ownedArtworks = ownedArtworks
        self.favoritedArtworks = favoritedArtworks
        self.collections = collections
        self.balance = balance
    }

    var formattedWallet: String {
        guard walletAddress.count > 10 else { return walletAddress }
        let prefix = walletAddress.prefix(6)
        let suffix = walletAddress.suffix(4)
        return "\(prefix)...\(suffix)"
    }

    var formattedBalance: String {
        String(format: "%.4f ETH", balance)
    }
}
