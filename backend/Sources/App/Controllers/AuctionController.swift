import Vapor
import Fluent

struct AuctionController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let auctions = routes.grouped("auctions")
        auctions.get(use: index)
        auctions.get(":auctionId", use: show)
        auctions.post(use: create)
        auctions.get(":auctionId", "bids", use: getBids)
    }

    // GET /api/v1/auctions?status=active
    func index(req: Request) async throws -> [AuctionDTO] {
        let status = req.query[String.self, at: "status"]

        var query = AuctionModel.query(on: req.db)

        if let status = status {
            query = query.filter(\.$status == status)
        }

        let auctions = try await query
            .with(\.$artwork)
            .sort(\.$endTime, .ascending)
            .all()

        return auctions.map { $0.toDTO() }
    }

    // GET /api/v1/auctions/:auctionId
    func show(req: Request) async throws -> AuctionDetailDTO {
        guard let auctionId = req.parameters.get("auctionId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid auction ID")
        }

        guard let auction = try await AuctionModel.query(on: req.db)
            .filter(\.$id == auctionId)
            .with(\.$artwork)
            .with(\.$bids)
            .first()
        else {
            throw Abort(.notFound, reason: "Auction not found")
        }

        // Load bid users separately
        for bid in auction.bids {
            try await bid.$user.load(on: req.db)
        }

        let bids = auction.bids
            .sorted { $0.amount > $1.amount }
            .map { bid in
                bid.toDTO(userName: bid.user.displayName)
            }

        return AuctionDetailDTO(
            auction: auction.toDTO(),
            artwork: auction.artwork.toDTO(),
            bids: bids
        )
    }

    // POST /api/v1/auctions
    func create(req: Request) async throws -> AuctionDTO {
        try CreateAuctionRequest.validate(content: req)
        let userId = try req.auth.require(UUID.self)
        let body = try req.content.decode(CreateAuctionRequest.self)

        guard let artworkId = UUID(uuidString: body.artworkId) else {
            throw Abort(.badRequest, reason: "Invalid artwork ID")
        }

        guard let artwork = try await ArtworkModel.find(artworkId, on: req.db) else {
            throw Abort(.notFound, reason: "Artwork not found")
        }

        guard artwork.$creator.id == userId else {
            throw Abort(.forbidden, reason: "You can only auction your own artworks")
        }

        let endTime = Date().addingTimeInterval(Double(body.durationHours) * 3600)
        let auction = AuctionModel(
            artworkId: artworkId,
            creatorId: userId,
            startingPrice: body.startingPrice,
            reservePrice: body.reservePrice,
            bidStep: body.bidStep ?? 0.01,
            endTime: endTime
        )

        try await auction.save(on: req.db)
        return auction.toDTO()
    }

    // GET /api/v1/auctions/:auctionId/bids
    func getBids(req: Request) async throws -> [BidDTO] {
        guard let auctionId = req.parameters.get("auctionId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid auction ID")
        }

        let bids = try await BidModel.query(on: req.db)
            .filter(\.$auction.$id == auctionId)
            .with(\.$user)
            .sort(\.$amount, .descending)
            .all()

        return bids.map { bid in
            bid.toDTO(userName: bid.user.displayName)
        }
    }
}
