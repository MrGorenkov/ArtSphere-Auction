import Foundation

/// Pure DTO → Domain mapping helpers used by `AuctionService` when bridging API
/// payloads to in-memory models. Kept separate so the service file stays focused on
/// state and side-effects.
extension AuctionService {

    static func mapArtworkDTO(_ api: APIArtwork) -> NFTArtwork {
        let category = mapStyleToCategoryName(api.styleName)
        let imageSource: NFTArtwork.ImageSource = api.imageUrl != nil ? .url : .procedural
        let blockchain: NFTArtwork.BlockchainNetwork = api.blockchain == "Ethereum" ? .ethereum : .polygon

        return NFTArtwork(
            id: UUID(uuidString: api.id) ?? UUID(),
            title: api.title,
            artistName: api.artistName,
            description: api.description,
            imageName: api.imageUrl ?? "artwork_\(api.id.prefix(8))",
            category: category,
            createdAt: ISO8601DateFormatter().date(from: api.createdAt) ?? Date(),
            blockchain: blockchain,
            imageSource: imageSource,
            imageURL: api.imageUrl,
            modelUrl: api.filePath
        )
    }

    static func mapAuctionDTO(_ api: APIAuction, artwork: NFTArtwork) -> Auction {
        let formatter = ISO8601DateFormatter()
        let status: Auction.AuctionStatus
        switch api.status {
        case "active":   status = .active
        case "upcoming": status = .upcoming
        case "sold":     status = .sold
        default:         status = .ended
        }

        return Auction(
            id: UUID(uuidString: api.id) ?? UUID(),
            artwork: artwork,
            startTime: formatter.date(from: api.startTime) ?? Date(),
            endTime: formatter.date(from: api.endTime) ?? Date(),
            currentBid: api.currentBid,
            bids: [],
            status: status,
            startingPrice: api.startingPrice,
            reservePrice: api.reservePrice,
            winnerId: api.winnerId.flatMap { UUID(uuidString: $0) },
            creatorId: api.creatorId.flatMap { UUID(uuidString: $0) },
            bidStep: api.bidStep,
            serverBidCount: api.bidCount,
            buyNowPrice: api.buyNowPrice
        )
    }

    static func mapBidDTO(_ api: APIBid) -> Bid {
        Bid(
            id: UUID(uuidString: api.id) ?? UUID(),
            userId: UUID(uuidString: api.userId) ?? UUID(),
            userName: api.userName,
            amount: api.amount,
            timestamp: ISO8601DateFormatter().date(from: api.timestamp) ?? Date()
        )
    }

    static func mapUserDTO(_ api: APIUser) -> User {
        User(
            id: UUID(uuidString: api.id) ?? UUID(),
            username: api.username,
            displayName: api.displayName,
            walletAddress: api.walletAddress,
            avatarUrl: api.avatarUrl,
            bio: api.bio ?? "",
            balance: api.balance
        )
    }

    static func mapCollectionDTO(_ api: APICollection) -> NFTCollection {
        NFTCollection(
            id: UUID(uuidString: api.id) ?? UUID(),
            name: api.name,
            description: api.description ?? "",
            artworkIds: api.artworkIds.compactMap { UUID(uuidString: $0) },
            isDefault: api.isDefault
        )
    }

    static func mapStyleToCategoryName(_ styleName: String?) -> NFTArtwork.ArtworkCategory {
        guard let name = styleName?.lowercased() else { return .digitalPainting }
        if name.contains("генеративн") || name.contains("generativ") { return .generativeArt }
        if name.contains("фото")       || name.contains("photo")     { return .photography }
        if name.contains("абстракц")   || name.contains("abstract")  { return .abstract }
        if name.contains("пиксел")     || name.contains("pixel")     { return .pixel }
        if name.contains("3d")         || name.contains("3д")        { return .threeD }
        return .digitalPainting
    }
}
