import Vapor
import Fluent
import FluentPostgresDriver

struct AdminController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let admin = routes.grouped("admin")
        admin.get("dashboard", use: dashboard)
        admin.get("users", use: listUsers)
        admin.put("users", ":userId", "toggle-active", use: toggleUserActive)
        admin.delete("users", ":userId", use: deleteUser)
        admin.get("artworks", use: listArtworks)
        admin.put("artworks", ":artworkId", use: updateArtwork)
        admin.delete("artworks", ":artworkId", use: deleteArtwork)
        admin.get("auctions", use: listAuctions)
        admin.put("auctions", ":auctionId", "cancel", use: cancelAuction)
        admin.get("auctions", ":auctionId", "bids", use: auctionBids)
    }

    // MARK: - Dashboard

    // GET /api/v1/admin/dashboard
    func dashboard(req: Request) async throws -> AdminDashboardDTO {
        let db = req.db as! SQLDatabase

        let usersRow = try await db.raw("SELECT COUNT(*) AS total, COUNT(*) FILTER (WHERE is_active) AS active FROM users").first()
        let totalUsers = try usersRow?.decode(column: "total", as: Int.self) ?? 0
        let activeUsers = try usersRow?.decode(column: "active", as: Int.self) ?? 0

        let artworksRow = try await db.raw("SELECT COUNT(*) AS total, COUNT(*) FILTER (WHERE is_published) AS published FROM artworks").first()
        let totalArtworks = try artworksRow?.decode(column: "total", as: Int.self) ?? 0
        let publishedArtworks = try artworksRow?.decode(column: "published", as: Int.self) ?? 0

        let auctionsRows = try await db.raw("""
            SELECT status, COUNT(*) AS cnt FROM auctions GROUP BY status
        """).all()

        var auctionsByStatus: [String: Int] = [:]
        for row in auctionsRows {
            let status = try row.decode(column: "status", as: String.self)
            let cnt = try row.decode(column: "cnt", as: Int.self)
            auctionsByStatus[status] = cnt
        }

        let totalBidsRow = try await db.raw("SELECT COUNT(*) AS cnt FROM bids").first()
        let totalBids = try totalBidsRow?.decode(column: "cnt", as: Int.self) ?? 0

        let revenueRow = try await db.raw("SELECT COALESCE(SUM(amount), 0) AS total FROM transactions WHERE status = 'completed'").first()
        let totalRevenue = try revenueRow?.decode(column: "total", as: Double.self) ?? 0.0

        return AdminDashboardDTO(
            totalUsers: totalUsers,
            activeUsers: activeUsers,
            totalArtworks: totalArtworks,
            publishedArtworks: publishedArtworks,
            auctionsByStatus: auctionsByStatus,
            totalBids: totalBids,
            totalRevenue: totalRevenue
        )
    }

    // MARK: - Users

    // GET /api/v1/admin/users
    func listUsers(req: Request) async throws -> [AdminUserDTO] {
        let db = req.db as! SQLDatabase
        let rows = try await db.raw("""
            SELECT id, username, display_name, email, wallet_address, avatar_url, bio,
                   balance, is_active, is_admin, created_at,
                   (SELECT COUNT(*) FROM artworks WHERE creator_id = u.id) AS artworks_count,
                   (SELECT COUNT(*) FROM bids WHERE user_id = u.id) AS bids_count
            FROM users u
            ORDER BY created_at DESC
        """).all()

        return try rows.map { row in
            AdminUserDTO(
                id: try row.decode(column: "id", as: UUID.self).uuidString,
                username: try row.decode(column: "username", as: String.self),
                displayName: try row.decode(column: "display_name", as: String.self),
                email: try? row.decode(column: "email", as: String.self),
                walletAddress: try row.decode(column: "wallet_address", as: String.self),
                avatarUrl: try? row.decode(column: "avatar_url", as: String.self),
                bio: try? row.decode(column: "bio", as: String.self),
                balance: try row.decode(column: "balance", as: Double.self),
                isActive: try row.decode(column: "is_active", as: Bool.self),
                isAdmin: try row.decode(column: "is_admin", as: Bool.self),
                createdAt: try row.decode(column: "created_at", as: Date.self).iso8601String,
                artworksCount: try row.decode(column: "artworks_count", as: Int.self),
                bidsCount: try row.decode(column: "bids_count", as: Int.self)
            )
        }
    }

    // PUT /api/v1/admin/users/:userId/toggle-active
    func toggleUserActive(req: Request) async throws -> AdminUserDTO {
        guard let userId = req.parameters.get("userId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid user ID")
        }

        guard let user = try await UserModel.find(userId, on: req.db) else {
            throw Abort(.notFound, reason: "User not found")
        }

        user.isActive.toggle()
        try await user.save(on: req.db)

        let db = req.db as! SQLDatabase
        let artworksRow = try await db.raw("SELECT COUNT(*) AS cnt FROM artworks WHERE creator_id = \(bind: userId)").first()
        let artworksCount = try artworksRow?.decode(column: "cnt", as: Int.self) ?? 0
        let bidsRow = try await db.raw("SELECT COUNT(*) AS cnt FROM bids WHERE user_id = \(bind: userId)").first()
        let bidsCount = try bidsRow?.decode(column: "cnt", as: Int.self) ?? 0

        return AdminUserDTO(
            id: user.id?.uuidString ?? "",
            username: user.username,
            displayName: user.displayName,
            email: user.email,
            walletAddress: user.walletAddress,
            avatarUrl: user.avatarUrl,
            bio: user.bio,
            balance: user.balance,
            isActive: user.isActive,
            isAdmin: user.isAdmin,
            createdAt: user.createdAt?.iso8601String ?? "",
            artworksCount: artworksCount,
            bidsCount: bidsCount
        )
    }

    // DELETE /api/v1/admin/users/:userId
    func deleteUser(req: Request) async throws -> HTTPStatus {
        guard let userId = req.parameters.get("userId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid user ID")
        }

        guard let user = try await UserModel.find(userId, on: req.db) else {
            throw Abort(.notFound, reason: "User not found")
        }

        guard !user.isAdmin else {
            throw Abort(.forbidden, reason: "Cannot delete admin user")
        }

        try await user.delete(on: req.db)
        return .noContent
    }

    // MARK: - Artworks

    // GET /api/v1/admin/artworks
    func listArtworks(req: Request) async throws -> [AdminArtworkDTO] {
        let db = req.db as! SQLDatabase
        let rows = try await db.raw("""
            SELECT a.id, a.title, a.artist_name, a.description, a.image_url,
                   a.price, a.is_for_sale, a.is_published, a.blockchain, a.created_at,
                   s.name AS style_name,
                   u.display_name AS creator_name,
                   (SELECT COUNT(*) FROM auctions WHERE artwork_id = a.id) AS auctions_count
            FROM artworks a
            LEFT JOIN art_styles s ON a.style_id = s.id
            LEFT JOIN users u ON a.creator_id = u.id
            ORDER BY a.created_at DESC
        """).all()

        return try rows.map { row in
            AdminArtworkDTO(
                id: try row.decode(column: "id", as: UUID.self).uuidString,
                title: try row.decode(column: "title", as: String.self),
                artistName: try row.decode(column: "artist_name", as: String.self),
                description: try row.decode(column: "description", as: String.self),
                imageUrl: try? row.decode(column: "image_url", as: String.self),
                price: try? row.decode(column: "price", as: Double.self),
                isForSale: try row.decode(column: "is_for_sale", as: Bool.self),
                isPublished: try row.decode(column: "is_published", as: Bool.self),
                blockchain: try row.decode(column: "blockchain", as: String.self),
                styleName: try? row.decode(column: "style_name", as: String.self),
                creatorName: try? row.decode(column: "creator_name", as: String.self),
                auctionsCount: try row.decode(column: "auctions_count", as: Int.self),
                createdAt: try row.decode(column: "created_at", as: Date.self).iso8601String
            )
        }
    }

    // PUT /api/v1/admin/artworks/:artworkId
    func updateArtwork(req: Request) async throws -> AdminArtworkDTO {
        guard let artworkId = req.parameters.get("artworkId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid artwork ID")
        }

        guard let artwork = try await ArtworkModel.find(artworkId, on: req.db) else {
            throw Abort(.notFound, reason: "Artwork not found")
        }

        let body = try req.content.decode(AdminUpdateArtworkRequest.self)
        if let title = body.title { artwork.title = title }
        if let description = body.description { artwork.description = description }
        if let isPublished = body.isPublished { artwork.isPublished = isPublished }
        if let isForSale = body.isForSale { artwork.isForSale = isForSale }

        try await artwork.save(on: req.db)

        let db = req.db as! SQLDatabase
        let auctionsRow = try await db.raw("SELECT COUNT(*) AS cnt FROM auctions WHERE artwork_id = \(bind: artworkId)").first()
        let auctionsCount = try auctionsRow?.decode(column: "cnt", as: Int.self) ?? 0

        return AdminArtworkDTO(
            id: artwork.id?.uuidString ?? "",
            title: artwork.title,
            artistName: artwork.artistName,
            description: artwork.description,
            imageUrl: artwork.imageUrl,
            price: artwork.price,
            isForSale: artwork.isForSale,
            isPublished: artwork.isPublished,
            blockchain: artwork.blockchain,
            styleName: nil,
            creatorName: nil,
            auctionsCount: auctionsCount,
            createdAt: artwork.createdAt?.iso8601String ?? ""
        )
    }

    // DELETE /api/v1/admin/artworks/:artworkId
    func deleteArtwork(req: Request) async throws -> HTTPStatus {
        guard let artworkId = req.parameters.get("artworkId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid artwork ID")
        }

        guard let artwork = try await ArtworkModel.find(artworkId, on: req.db) else {
            throw Abort(.notFound, reason: "Artwork not found")
        }

        try await artwork.delete(on: req.db)
        return .noContent
    }

    // MARK: - Auctions

    // GET /api/v1/admin/auctions
    func listAuctions(req: Request) async throws -> [AdminAuctionDTO] {
        let db = req.db as! SQLDatabase
        let rows = try await db.raw("""
            SELECT a.id, a.starting_price, a.current_bid, a.reserve_price, a.bid_step,
                   a.start_time, a.end_time, a.status, a.bid_count,
                   a.winner_id, a.created_at,
                   aw.title AS artwork_title, aw.image_url AS artwork_image_url,
                   u.display_name AS creator_name,
                   w.display_name AS winner_name
            FROM auctions a
            JOIN artworks aw ON a.artwork_id = aw.id
            LEFT JOIN users u ON a.creator_id = u.id
            LEFT JOIN users w ON a.winner_id = w.id
            ORDER BY a.created_at DESC
        """).all()

        return try rows.map { row in
            AdminAuctionDTO(
                id: try row.decode(column: "id", as: UUID.self).uuidString,
                artworkTitle: try row.decode(column: "artwork_title", as: String.self),
                artworkImageUrl: try? row.decode(column: "artwork_image_url", as: String.self),
                startingPrice: try row.decode(column: "starting_price", as: Double.self),
                currentBid: try row.decode(column: "current_bid", as: Double.self),
                reservePrice: try? row.decode(column: "reserve_price", as: Double.self),
                bidStep: try row.decode(column: "bid_step", as: Double.self),
                startTime: try row.decode(column: "start_time", as: Date.self).iso8601String,
                endTime: try row.decode(column: "end_time", as: Date.self).iso8601String,
                status: try row.decode(column: "status", as: String.self),
                bidCount: try row.decode(column: "bid_count", as: Int.self),
                creatorName: try? row.decode(column: "creator_name", as: String.self),
                winnerName: try? row.decode(column: "winner_name", as: String.self),
                createdAt: try row.decode(column: "created_at", as: Date.self).iso8601String
            )
        }
    }

    // PUT /api/v1/admin/auctions/:auctionId/cancel
    func cancelAuction(req: Request) async throws -> AdminAuctionDTO {
        guard let auctionId = req.parameters.get("auctionId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid auction ID")
        }

        guard let auction = try await AuctionModel.find(auctionId, on: req.db) else {
            throw Abort(.notFound, reason: "Auction not found")
        }

        guard auction.status == "active" || auction.status == "upcoming" else {
            throw Abort(.badRequest, reason: "Can only cancel active or upcoming auctions")
        }

        auction.status = "ended"
        try await auction.save(on: req.db)

        let db = req.db as! SQLDatabase
        let artworkRow = try await db.raw("SELECT title, image_url FROM artworks WHERE id = \(bind: auction.$artwork.id)").first()
        let artworkTitle = try artworkRow?.decode(column: "title", as: String.self) ?? "Unknown"
        let artworkImageUrl = try? artworkRow?.decode(column: "image_url", as: String.self)

        return AdminAuctionDTO(
            id: auction.id?.uuidString ?? "",
            artworkTitle: artworkTitle,
            artworkImageUrl: artworkImageUrl,
            startingPrice: auction.startingPrice,
            currentBid: auction.currentBid,
            reservePrice: auction.reservePrice,
            bidStep: auction.bidStep,
            startTime: auction.startTime.iso8601String,
            endTime: auction.endTime.iso8601String,
            status: auction.status,
            bidCount: auction.bidCount,
            creatorName: nil,
            winnerName: nil,
            createdAt: auction.createdAt?.iso8601String ?? ""
        )
    }

    // GET /api/v1/admin/auctions/:auctionId/bids
    func auctionBids(req: Request) async throws -> [BidDTO] {
        guard let auctionId = req.parameters.get("auctionId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid auction ID")
        }

        let db = req.db as! SQLDatabase
        let rows = try await db.raw("""
            SELECT b.id, b.auction_id, b.user_id, b.amount, b.created_at,
                   u.display_name AS user_name
            FROM bids b
            JOIN users u ON b.user_id = u.id
            WHERE b.auction_id = \(bind: auctionId)
            ORDER BY b.amount DESC
        """).all()

        return try rows.map { row in
            BidDTO(
                id: try row.decode(column: "id", as: UUID.self).uuidString,
                auctionId: try row.decode(column: "auction_id", as: UUID.self).uuidString,
                userId: try row.decode(column: "user_id", as: UUID.self).uuidString,
                userName: try row.decode(column: "user_name", as: String.self),
                amount: try row.decode(column: "amount", as: Double.self),
                timestamp: try row.decode(column: "created_at", as: Date.self).iso8601String
            )
        }
    }
}

// MARK: - Admin DTOs

struct AdminDashboardDTO: Content {
    let totalUsers: Int
    let activeUsers: Int
    let totalArtworks: Int
    let publishedArtworks: Int
    let auctionsByStatus: [String: Int]
    let totalBids: Int
    let totalRevenue: Double
}

struct AdminUserDTO: Content {
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

struct AdminArtworkDTO: Content {
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

struct AdminAuctionDTO: Content {
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

struct AdminUpdateArtworkRequest: Content {
    let title: String?
    let description: String?
    let isPublished: Bool?
    let isForSale: Bool?
}
