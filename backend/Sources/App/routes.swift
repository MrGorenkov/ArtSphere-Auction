import Vapor

func routes(_ app: Application) throws {
    // Health check
    app.get { req in
        return ["status": "ok", "service": "NFT Arts API", "version": "1.0"]
    }

    // API v1
    let api = app.grouped("api", "v1")

    // Public routes
    try api.register(collection: AuthController())

    // Public: art styles (no auth required)
    try api.register(collection: ArtStyleController())

    // Protected routes (require JWT)
    let protected = api.grouped(JWTAuthMiddleware())
    try protected.register(collection: ArtworkController())
    try protected.register(collection: AuctionController())
    try protected.register(collection: BidController())
    try protected.register(collection: UserController())
    try protected.register(collection: CollectionController())
    try protected.register(collection: NFTTokenController())
    try protected.register(collection: TransactionController())

    // ============================================
    // WebSocket: real-time аукционные обновления
    // ws://host:8080/ws/auction/:auctionId
    // ============================================
    app.webSocket("ws", "auction", ":auctionId") { req, ws in
        guard let auctionIdString = req.parameters.get("auctionId"),
              let auctionId = UUID(uuidString: auctionIdString) else {
            try? await ws.close()
            return
        }

        // Подписать клиента на обновления аукциона
        await WebSocketManager.shared.subscribe(to: auctionId, socket: ws)

        // Отправить текущее состояние аукциона при подключении
        if let auction = try? await AuctionModel.find(auctionId, on: req.db) {
            let status = WSAuctionUpdate(
                type: "auction_status",
                auctionId: auctionId.uuidString,
                status: auction.status,
                winnerId: auction.winnerId?.uuidString
            )
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(status),
               let json = String(data: data, encoding: .utf8) {
                try? await ws.send(json)
            }
        }

        // При закрытии — отписать
        ws.onClose.whenComplete { _ in
            Task {
                await WebSocketManager.shared.unsubscribe(from: auctionId, socket: ws)
            }
        }
    }

    // ============================================
    // WebSocket: global auction feed (all bid + status updates)
    // ws://host:8080/ws/auctions/feed
    // ============================================
    app.webSocket("ws", "auctions", "feed") { req, ws in
        await WebSocketManager.shared.subscribeFeed(socket: ws)

        ws.onClose.whenComplete { _ in
            Task {
                await WebSocketManager.shared.unsubscribeFeed(socket: ws)
            }
        }
    }

    // ws://host:8080/ws/user/:userId — персональные уведомления
    app.webSocket("ws", "user", ":userId") { req, ws in
        guard let userIdString = req.parameters.get("userId"),
              let userId = UUID(uuidString: userIdString) else {
            try? await ws.close()
            return
        }

        await WebSocketManager.shared.connectUser(userId, socket: ws)

        ws.onClose.whenComplete { _ in
            Task {
                await WebSocketManager.shared.disconnectUser(userId, socket: ws)
            }
        }
    }
}
