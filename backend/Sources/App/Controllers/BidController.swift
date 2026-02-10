import Vapor
import Fluent

struct BidController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let bids = routes.grouped("bids")
        bids.post(use: placeBid)
    }

    // POST /api/v1/bids
    func placeBid(req: Request) async throws -> BidDTO {
        try PlaceBidRequest.validate(content: req)
        let userId = try req.auth.require(UUID.self)
        let body = try req.content.decode(PlaceBidRequest.self)

        guard let auctionId = UUID(uuidString: body.auctionId) else {
            throw Abort(.badRequest, reason: "Invalid auction ID")
        }

        // Get auction
        guard let auction = try await AuctionModel.find(auctionId, on: req.db) else {
            throw Abort(.notFound, reason: "Auction not found")
        }

        // Validate auction is active
        guard auction.status == "active" else {
            throw Abort(.badRequest, reason: "Auction is not active")
        }

        guard auction.endTime > Date() else {
            throw Abort(.badRequest, reason: "Auction has ended")
        }

        // Validate bid amount (must be >= current + bid_step)
        let minimumBid = max(auction.currentBid + auction.bidStep, auction.startingPrice)
        guard body.amount >= minimumBid else {
            throw Abort(.badRequest, reason: "Bid must be at least \(String(format: "%.2f", minimumBid)) ETH")
        }

        // Check user balance
        guard let user = try await UserModel.find(userId, on: req.db) else {
            throw Abort(.notFound, reason: "User not found")
        }

        guard user.balance >= body.amount else {
            throw Abort(.badRequest, reason: "Insufficient balance")
        }

        // Place bid (DB trigger will update auction)
        let bid = BidModel(
            auctionId: auctionId,
            userId: userId,
            amount: body.amount
        )

        try await bid.save(on: req.db)

        let bidDTO = bid.toDTO(userName: user.displayName)

        // WebSocket: broadcast new bid to all subscribers
        let wsMessage = WSBidMessage(
            type: "new_bid",
            auctionId: auctionId.uuidString,
            bid: bidDTO,
            currentBid: body.amount,
            bidCount: auction.bidCount + 1
        )
        await WebSocketManager.shared.broadcastBid(wsMessage, auctionId: auctionId)

        return bidDTO
    }
}
