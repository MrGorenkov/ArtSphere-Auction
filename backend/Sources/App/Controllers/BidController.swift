import Vapor
import Fluent

struct BidController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let bids = routes.grouped("bids")
        bids.post(use: placeBid)

        let sync = routes.grouped("sync")
        sync.post("bids", use: syncBids)
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

        // Remember previous high bidder for outbid notification
        let previousHighBidder = try await BidModel.query(on: req.db)
            .filter(\.$auction.$id == auctionId)
            .sort(\.$amount, .descending)
            .first()

        // Place bid (DB trigger will update auction's current_bid and bid_count)
        let bid = BidModel(
            auctionId: auctionId,
            userId: userId,
            amount: body.amount
        )

        try await bid.save(on: req.db)

        let bidDTO = bid.toDTO(userName: user.displayName)

        // WebSocket: broadcast new bid to all auction subscribers
        let wsMessage = WSBidMessage(
            type: "new_bid",
            auctionId: auctionId.uuidString,
            bid: bidDTO,
            currentBid: body.amount,
            bidCount: auction.bidCount + 1
        )
        await WebSocketManager.shared.broadcastBid(wsMessage, auctionId: auctionId)

        // Notify previous high bidder they've been outbid
        if let prevBid = previousHighBidder, prevBid.$user.id != userId {
            let outbidMsg = """
            {"type":"outbid","title":"Outbid!","message":"\(user.displayName) outbid you on the auction","auctionId":"\(auctionId.uuidString)"}
            """
            await WebSocketManager.shared.sendToUser(prevBid.$user.id, message: outbidMsg)
        }

        return bidDTO
    }

    // POST /api/v1/sync/bids — batch-sync queued offline bids
    func syncBids(req: Request) async throws -> SyncBidResponse {
        let userId = try req.auth.require(UUID.self)
        let inputs = try req.content.decode([SyncBidInput].self)

        guard let user = try await UserModel.find(userId, on: req.db) else {
            throw Abort(.notFound, reason: "User not found")
        }

        var synced: [String] = []
        var failed: [String] = []

        for input in inputs {
            guard let auctionId = UUID(uuidString: input.auctionId) else {
                failed.append(input.id)
                continue
            }

            guard let auction = try await AuctionModel.find(auctionId, on: req.db) else {
                failed.append(input.id)
                continue
            }

            // Skip ended/sold auctions and insufficient amounts
            let minimumBid = max(auction.currentBid + auction.bidStep, auction.startingPrice)
            guard auction.status == "active",
                  auction.endTime > Date(),
                  input.amount >= minimumBid,
                  user.balance >= input.amount else {
                failed.append(input.id)
                continue
            }

            let bid = BidModel(
                auctionId: auctionId,
                userId: userId,
                amount: input.amount,
                synced: true
            )
            try await bid.save(on: req.db)
            synced.append(input.id)

            // WebSocket broadcast
            let bidDTO = bid.toDTO(userName: user.displayName)
            let wsMessage = WSBidMessage(
                type: "new_bid",
                auctionId: auctionId.uuidString,
                bid: bidDTO,
                currentBid: input.amount,
                bidCount: auction.bidCount + 1
            )
            await WebSocketManager.shared.broadcastBid(wsMessage, auctionId: auctionId)
        }

        return SyncBidResponse(synced: synced, failed: failed)
    }
}

// MARK: - Sync DTOs

struct SyncBidInput: Content {
    let id: String
    let auctionId: String
    let amount: Double
    let timestamp: String
}

struct SyncBidResponse: Content {
    let synced: [String]
    let failed: [String]
}
