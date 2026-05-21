import Vapor
import Fluent

struct BidController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let bids = routes.grouped("bids")
        bids.post(use: placeBid)
        bids.post("autobroker", use: setAutoBroker) // <-- Новый роут

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

        guard let auction = try await AuctionModel.find(auctionId, on: req.db) else {
            throw Abort(.notFound, reason: "Auction not found")
        }

        guard auction.status == "active", auction.endTime > Date() else {
            throw Abort(.badRequest, reason: "Auction is not active or has ended")
        }

        let minimumBid = max(auction.currentBid + auction.bidStep, auction.startingPrice)
        guard body.amount >= minimumBid else {
            throw Abort(.badRequest, reason: "Bid must be at least \(String(format: "%.2f", minimumBid)) TON")
        }

        guard let user = try await UserModel.find(userId, on: req.db) else {
            throw Abort(.notFound, reason: "User not found")
        }

        guard user.balance >= body.amount else {
            throw Abort(.badRequest, reason: "Insufficient balance")
        }

        let previousHighBidder = try await BidModel.query(on: req.db)
            .filter(\.$auction.$id == auctionId)
            .sort(\.$amount, .descending)
            .with(\.$user)
            .first()

        // Escrow-логика:
        // 1) Возвращаем предыдущую активную ставку её владельцу (даже если это тот же юзер —
        //    иначе при self-overbid он теряет старую сумму, см. отчёт user 2026-05-19).
        // 2) Списываем новую ставку с user.balance (его деньги уходят в эскроу аукциона).
        if let prevBid = previousHighBidder {
            if prevBid.$user.id == userId {
                // Та же сессия Fluent-юзера — модифицируем `user`, не `prevBid.user`,
                // чтобы не было двух копий и кто-то не перетёр другого.
                user.balance += prevBid.amount
            } else {
                prevBid.user.balance += prevBid.amount
                try await prevBid.user.save(on: req.db)
            }
        }

        user.balance -= body.amount
        try await user.save(on: req.db)

        let bid = BidModel(auctionId: auctionId, userId: userId, amount: body.amount)
        try await bid.save(on: req.db)

        // Rewards: volume для buyer-уровня + cashback + level-up бонус (atomically).
        try await RewardsEngine.onBidPlaced(user: user, amount: body.amount, on: req.db)

        let bidDTO = bid.toDTO(userName: user.displayName)

        let wsMessage = WSBidMessage(
            type: "new_bid",
            auctionId: auctionId.uuidString,
            bid: bidDTO,
            currentBid: body.amount,
            bidCount: auction.bidCount + 1
        )
        await WebSocketManager.shared.broadcastBid(wsMessage, auctionId: auctionId)

        if let prevBid = previousHighBidder, prevBid.$user.id != userId {
            let outbidMsg = """
            {"type":"outbid","title":"Вашу ставку перебили!","message":"Пользователь \(user.displayName) перебил вашу ставку","auctionId":"\(auctionId.uuidString)"}
            """
            await WebSocketManager.shared.sendToUser(prevBid.$user.id, message: outbidMsg)
        }

        // ⚡️ Запуск Авто-Брокера через сериализатор:
        // несколько параллельных ставок на один аукцион сольются в одну очередь,
        // чтобы исключить race condition (дубликаты ставок от того же брокера).
        let appDb = req.application.db
        Task {
            await AutoBrokerSerializer.shared.run(auctionId: auctionId) {
                try? await Self.processAutoBroker(auctionId: auctionId, db: appDb)
            }
        }

        return bidDTO
    }

    // POST /api/v1/bids/autobroker
    func setAutoBroker(req: Request) async throws -> HTTPStatus {
        try SetAutoBrokerRequest.validate(content: req)
        let userId = try req.auth.require(UUID.self)
        let body = try req.content.decode(SetAutoBrokerRequest.self)

        guard let auctionId = UUID(uuidString: body.auctionId) else {
            throw Abort(.badRequest, reason: "Invalid auction ID")
        }

        guard let auction = try await AuctionModel.find(auctionId, on: req.db), auction.status == "active" else {
            throw Abort(.badRequest, reason: "Auction is not active")
        }

        // Upsert настроек
        if let existing = try await AutoBrokerSettingModel.query(on: req.db)
            .filter(\.$user.$id == userId)
            .filter(\.$auction.$id == auctionId)
            .first() {
            existing.maxAmount = body.maxAmount
            try await existing.save(on: req.db)
        } else {
            let newSetting = AutoBrokerSettingModel(userId: userId, auctionId: auctionId, maxAmount: body.maxAmount)
            try await newSetting.save(on: req.db)
        }

        // Запуск проверки через сериализатор (см. placeBid)
        let appDb = req.application.db
        Task {
            await AutoBrokerSerializer.shared.run(auctionId: auctionId) {
                try? await Self.processAutoBroker(auctionId: auctionId, db: appDb)
            }
        }

        return .ok
    }

    // ⚡️ ЯДРО АВТО-БРОКЕРА.
    // static — чтобы вызываться из @Sendable closure (см. AutoBrokerSerializer).
    static func processAutoBroker(auctionId: UUID, db: Database) async throws {
        var safetyCounter = 0
        let maxLadderSteps = 50 // защита от бесконечного цикла на случай неожиданных условий

        while safetyCounter < maxLadderSteps {
            safetyCounter += 1

            guard let auction = try await AuctionModel.find(auctionId, on: db) else { return }
            guard auction.status == "active", auction.endTime > Date() else { return }

            let previousHighBidder = try await BidModel.query(on: db)
                .filter(\.$auction.$id == auctionId)
                .sort(\.$amount, .descending)
                .with(\.$user)
                .first()

            let currentHighBidderId = previousHighBidder?.$user.id
            let nextBidAmount = max(auction.currentBid + auction.bidStep, auction.startingPrice)

            let candidateBrokers = try await AutoBrokerSettingModel.query(on: db)
                .filter(\.$auction.$id == auctionId)
                .filter(\.$maxAmount >= nextBidAmount)
                .with(\.$user)
                .all()

            let validBrokers = candidateBrokers.filter {
                $0.$user.id != currentHighBidderId && $0.user.balance >= nextBidAmount
            }

            guard let winnerBroker = validBrokers.sorted(by: {
                if $0.maxAmount == $1.maxAmount {
                    return ($0.createdAt ?? Date()) < ($1.createdAt ?? Date())
                }
                return $0.maxAmount > $1.maxAmount
            }).first else {
                return
            }

            // Escrow: возвращаем предыдущую ставку владельцу (даже если это тот же юзер),
            // затем списываем новую с winnerBroker.
            if let prevBid = previousHighBidder {
                if prevBid.$user.id == winnerBroker.$user.id {
                    winnerBroker.user.balance += prevBid.amount
                } else {
                    prevBid.user.balance += prevBid.amount
                    try await prevBid.user.save(on: db)
                }
            }
            winnerBroker.user.balance -= nextBidAmount
            try await winnerBroker.user.save(on: db)

            let newBid = BidModel(auctionId: auctionId, userId: winnerBroker.$user.id, amount: nextBidAmount)
            try await newBid.save(on: db)
            // Авто-брокер тоже триггерит rewards для своего владельца.
            try await RewardsEngine.onBidPlaced(user: winnerBroker.user, amount: nextBidAmount, on: db)

            // Считаем актуальное количество ставок свежим запросом —
            // на лесенке из нескольких авто-ставок нельзя полагаться на закэшированный auction.bidCount.
            let freshBidCount = try await BidModel.query(on: db)
                .filter(\.$auction.$id == auctionId)
                .count()

            let bidDTO = newBid.toDTO(userName: winnerBroker.user.displayName)
            let wsMessage = WSBidMessage(
                type: "new_bid",
                auctionId: auctionId.uuidString,
                bid: bidDTO,
                currentBid: nextBidAmount,
                bidCount: Int(freshBidCount)
            )
            await WebSocketManager.shared.broadcastBid(wsMessage, auctionId: auctionId)

            if let prevBid = previousHighBidder, prevBid.$user.id != winnerBroker.$user.id {
                let outbidMsg = """
                {"type":"outbid","title":"Вашу ставку перебили!","message":"Сработал авто-брокер пользователя \(winnerBroker.user.displayName)","auctionId":"\(auctionId.uuidString)"}
                """
                await WebSocketManager.shared.sendToUser(prevBid.$user.id, message: outbidMsg)
            }
        }
    }

    // POST /api/v1/sync/bids
    func syncBids(req: Request) async throws -> SyncBidResponse {
        let userId = try req.auth.require(UUID.self)
        let inputs = try req.content.decode([SyncBidInput].self)

        guard let user = try await UserModel.find(userId, on: req.db) else {
            throw Abort(.notFound, reason: "User not found")
        }

        var synced: [String] = []
        var failed: [String] = []

        for input in inputs {
            guard let auctionId = UUID(uuidString: input.auctionId),
                  let auction = try await AuctionModel.find(auctionId, on: req.db) else {
                failed.append(input.id)
                continue
            }

            let minimumBid = max(auction.currentBid + auction.bidStep, auction.startingPrice)
            guard auction.status == "active",
                  auction.endTime > Date(),
                  input.amount >= minimumBid,
                  user.balance >= input.amount else {
                failed.append(input.id)
                continue
            }

            // Escrow для offline-синхронизированной ставки: те же правила.
            let previousHighBidder = try await BidModel.query(on: req.db)
                .filter(\.$auction.$id == auctionId)
                .sort(\.$amount, .descending)
                .with(\.$user)
                .first()

            if let prevBid = previousHighBidder {
                if prevBid.$user.id == userId {
                    user.balance += prevBid.amount
                } else {
                    prevBid.user.balance += prevBid.amount
                    try await prevBid.user.save(on: req.db)
                }
            }
            user.balance -= input.amount
            try await user.save(on: req.db)

            let bid = BidModel(auctionId: auctionId, userId: userId, amount: input.amount, synced: true)
            try await bid.save(on: req.db)
            synced.append(input.id)

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