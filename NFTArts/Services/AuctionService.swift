import Foundation
import Combine
import SwiftUI

final class AuctionService: ObservableObject {
    static let shared = AuctionService()

    @Published var auctions: [Auction] = []
    @Published var featuredAuctions: [Auction] = []
    @Published var currentUser: User
    @Published var notifications: [AuctionNotification] = []
    @Published var wonAuctions: [Auction] = []
    @Published var artStyles: [APIArtStyle] = []
    @Published var completedAuctions: [Auction] = []
    @Published var autoBrokerSettings: [UUID: [UUID: Double]] = [:] // userId -> [auctionId -> maxAmount]
    @Published var isOnline = false
    @Published var isLoadingFromAPI = false

    private var auctionTimer: Timer?
    private var botBidTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let network = NetworkService.shared
    private let webSocket = WebSocketService.shared
    private let analytics = AnalyticsService.shared
    private let bidQueue = BidQueueService.shared

    private var artworkCache: [String: NFTArtwork] = [:]

    private init() {
        self.currentUser = Self.makeMockUser()

        webSocket.$latestBidUpdate
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                Task { @MainActor in
                    self?.handleWSBidUpdate(update)
                }
            }
            .store(in: &cancellables)

        webSocket.$latestAuctionUpdate
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                Task { @MainActor in
                    self?.handleWSAuctionUpdate(update)
                }
            }
            .store(in: &cancellables)

        webSocket.$latestUserNotification
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                Task { @MainActor in
                    self?.handleWSUserNotification(notification)
                }
            }
            .store(in: &cancellables)

        startAuctionMonitoring()
    }

    private var lastLoadedUserId: UUID?

    // MARK: - Load from API

    func loadFromAPI() async {
        await MainActor.run { isLoadingFromAPI = true }
        let apiStart = CFAbsoluteTimeGetCurrent()

        do {
            let styles = try await network.fetchStyles()
            await MainActor.run { artStyles = styles }

            async let artworksTask = network.fetchArtworks()
            async let auctionsTask = network.fetchAuctions(status: "active")

            let apiArtworks = try await artworksTask
            let apiAuctions = try await auctionsTask

            var cache: [String: NFTArtwork] = [:]
            for apiArt in apiArtworks {
                let artwork = Self.mapArtworkDTO(apiArt)
                cache[apiArt.id] = artwork
            }

            var mappedAuctions: [Auction] = []
            for apiAuction in apiAuctions {
                if let artwork = cache[apiAuction.artworkId] {
                    let auction = Self.mapAuctionDTO(apiAuction, artwork: artwork)
                    mappedAuctions.append(auction)
                }
            }

            if network.authToken != nil {
                do {
                    let apiUser = try await network.fetchProfile()
                    let user = Self.mapUserDTO(apiUser)

                    let apiCollections = try await network.fetchCollections()
                    var mappedUser = user
                    mappedUser.collections = apiCollections.map { Self.mapCollectionDTO($0) }

                    await MainActor.run {
                        // Only preserve ownedArtworks if same user (not switching accounts)
                        let isSameUser = self.lastLoadedUserId == mappedUser.id
                        let previousOwned = isSameUser ? self.currentUser.ownedArtworks : []
                        self.currentUser = mappedUser
                        self.lastLoadedUserId = mappedUser.id
                        // Restore locally-tracked ownedArtworks
                        for artworkId in previousOwned where !self.currentUser.ownedArtworks.contains(artworkId) {
                            self.currentUser.ownedArtworks.append(artworkId)
                        }
                    }

                    webSocket.subscribeToUser(apiUser.id)
                } catch {
                    print("Profile load failed: \(error)")
                }
            }

            await MainActor.run {
                // Preserve locally-created auctions that aren't on the server yet
                let serverIds = Set(mappedAuctions.map { $0.id })
                let localOnly = self.auctions.filter { auction in
                    !serverIds.contains(auction.id) && auction.artwork.imageSource == .uploaded
                }
                self.artworkCache = cache
                self.auctions = mappedAuctions + localOnly
                self.featuredAuctions = Array(self.auctions.prefix(3))
                self.isOnline = true
                self.isLoadingFromAPI = false

                // Compute ownedArtworks from sold auctions where current user won
                let wonArtworkIds = self.auctions
                    .filter { $0.status == .sold && $0.winnerId == self.currentUser.id }
                    .map { $0.artwork.id }
                for artworkId in wonArtworkIds where !self.currentUser.ownedArtworks.contains(artworkId) {
                    self.currentUser.ownedArtworks.append(artworkId)
                }
            }

            let apiElapsed = (CFAbsoluteTimeGetCurrent() - apiStart) * 1000
            MetricsService.shared.record(category: "network", name: "fetch_artworks_ms", value: apiElapsed, unit: "ms")

            // Subscribe to global auction feed via WebSocket
            webSocket.subscribeToAuctionFeed()

            // Sync any queued offline bids
            if bidQueue.hasPendingBids {
                bidQueue.syncQueue()
            }

        } catch {
            print("API load failed: \(error)")

            // Expired/invalid JWT — drop the session and let the auth gate show LoginView,
            // instead of showing a misleading "no connection" banner.
            if case APIError.unauthorized = error {
                await MainActor.run {
                    self.isLoadingFromAPI = false
                    AuthManager.shared.logout()
                }
                return
            }

            await MainActor.run {
                self.isOnline = false
                self.isLoadingFromAPI = false
                ErrorBannerService.shared.showOffline { [weak self] in
                    Task { await self?.loadFromAPI() }
                }
            }
            // Only load mock data if we have no existing auctions
            if await MainActor.run(body: { self.auctions.isEmpty }) {
                await loadLocalData()
            }
        }
    }

    private func loadLocalData() async {
        let allAuctions = Self.makeMockAuctions()
        await MainActor.run {
            self.auctions = allAuctions
            self.featuredAuctions = Array(allAuctions.prefix(3))
            let defaultCollection = NFTCollection(
                name: "My NFTs",
                description: "All collected artworks",
                isDefault: true
            )
            self.currentUser.collections = [defaultCollection]
        }
        startBotBidding()
    }

    // MARK: - Auction Monitoring

    private func startAuctionMonitoring() {
        auctionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkAuctionStatuses()
        }
    }

    private func checkAuctionStatuses() {
        var updated = false
        for i in auctions.indices {
            if auctions[i].status == .active && auctions[i].timeRemaining <= 0 {
                finalizeAuction(at: i)
                updated = true
            } else if auctions[i].status == .upcoming && auctions[i].startTime <= Date() {
                auctions[i].status = .active
                updated = true
            }
        }
        if updated { objectWillChange.send() }
    }

    private func finalizeAuction(at index: Int) {
        guard index < auctions.count else { return }

        if let highestBid = auctions[index].highestBid {
            auctions[index].status = .sold
            auctions[index].winnerId = highestBid.userId

            if highestBid.userId == currentUser.id {
                let artworkId = auctions[index].artwork.id
                if !currentUser.ownedArtworks.contains(artworkId) {
                    currentUser.ownedArtworks.append(artworkId)
                    if let defaultIdx = currentUser.collections.firstIndex(where: { $0.isDefault }) {
                        currentUser.collections[defaultIdx].artworkIds.append(artworkId)
                    }
                    wonAuctions.append(auctions[index])
                    addNotification(title: L10n.auctionWon, message: L10n.auctionWonNotif(auctions[index].artwork.title, highestBid.formattedAmount), type: .auctionWon)
                }
            } else {
                addNotification(title: L10n.auctionEndedTitle, message: L10n.auctionEndedSold(auctions[index].artwork.title, highestBid.userName), type: .auctionEnded)
            }
        } else {
            auctions[index].status = .ended
            addNotification(title: L10n.auctionEndedTitle, message: L10n.auctionEndedNoBids(auctions[index].artwork.title), type: .auctionEnded)
        }
    }

    // MARK: - WebSocket Handlers

    @MainActor
    private func handleWSBidUpdate(_ update: WebSocketService.WSBidUpdate) {
        guard let index = auctions.firstIndex(where: { $0.id.uuidString.lowercased() == update.auctionId.lowercased() }) else { return }

        let bid = Bid(
            id: UUID(uuidString: update.bid.id) ?? UUID(),
            userId: UUID(uuidString: update.bid.userId) ?? UUID(),
            userName: update.bid.userName,
            amount: update.bid.amount,
            timestamp: ISO8601DateFormatter().date(from: update.bid.timestamp) ?? Date()
        )

        auctions[index].bids.append(bid)
        auctions[index].currentBid = update.currentBid

        if bid.userId != currentUser.id {
            addNotification(title: L10n.newBid, message: L10n.newBidNotif(bid.userName, bid.formattedAmount, auctions[index].artwork.title), type: .newBid)

            // Auto-broker: counter-bid if outbid and auto-broker is set
            let auctionId = auctions[index].id
            let userId = currentUser.id
            if let maxAmount = autoBrokerSettings[userId]?[auctionId], auctions[index].isActive {
                let nextBid = auctions[index].minimumNextBid
                if nextBid <= maxAmount {
                    _ = placeBid(on: auctionId, amount: nextBid)
                    addNotification(title: L10n.autoBrokerTitle, message: L10n.autoBrokerPlaced(String(format: "%.2f ETH", nextBid)), type: .bidPlaced)
                } else {
                    autoBrokerSettings[userId]?[auctionId] = nil
                    addNotification(title: L10n.autoBrokerTitle, message: L10n.autoBrokerLimitReached, type: .bidPlaced)
                }
            }
        }
    }

    @MainActor
    private func handleWSAuctionUpdate(_ update: WebSocketService.WSAuctionStatusUpdate) {
        guard let index = auctions.firstIndex(where: { $0.id.uuidString.lowercased() == update.auctionId.lowercased() }) else { return }

        switch update.status {
        case "sold":
            auctions[index].status = .sold
            if let winnerId = update.winnerId { auctions[index].winnerId = UUID(uuidString: winnerId) }
        case "ended":
            auctions[index].status = .ended
        default: break
        }
    }

    @MainActor
    private func handleWSUserNotification(_ notification: WebSocketService.WSUserNotification) {
        switch notification.type {
        case "outbid":
            addNotification(
                title: notification.title ?? "Outbid!",
                message: notification.message ?? "Someone outbid you",
                type: .newBid
            )
        case "auction_won":
            addNotification(
                title: notification.title ?? "Auction Won!",
                message: notification.message ?? "Congratulations!",
                type: .auctionWon
            )
        default:
            if let title = notification.title, let message = notification.message {
                addNotification(title: title, message: message, type: .newBid)
            }
        }
    }

    // MARK: - Fetch Bids from API

    func fetchBidsForAuction(_ auctionId: UUID) {
        guard isOnline else { return }
        Task {
            do {
                let apiBids = try await network.fetchBids(auctionId: auctionId.uuidString)
                let mappedBids = apiBids.map { Self.mapBidDTO($0) }
                await MainActor.run {
                    if let index = self.auctions.firstIndex(where: { $0.id == auctionId }) {
                        self.auctions[index].bids = mappedBids
                    }
                }
            } catch {
                print("Failed to fetch bids: \(error)")
            }
        }
    }

    // MARK: - Profile & Stats

    @Published var userStats: APIUserStats?
    @Published var apiNotifications: [APINotification] = []

    func fetchUserStats() {
        guard isOnline else { return }
        Task {
            do {
                let stats = try await network.fetchStats()
                await MainActor.run { self.userStats = stats }
            } catch {
                print("Failed to fetch stats: \(error)")
            }
        }
    }

    func fetchAPINotifications() {
        guard isOnline else { return }
        Task {
            do {
                let notes = try await network.fetchNotifications()
                await MainActor.run { self.apiNotifications = notes }
            } catch {
                print("Failed to fetch notifications: \(error)")
            }
        }
    }

    func updateProfile(displayName: String, bio: String) {
        currentUser.displayName = displayName
        currentUser.bio = bio
        guard isOnline else { return }
        Task {
            do {
                let updated = try await network.updateProfile(displayName: displayName, bio: bio, avatarUrl: nil)
                await MainActor.run {
                    self.currentUser.displayName = updated.displayName
                    self.currentUser.bio = updated.bio ?? ""
                    self.currentUser.avatarUrl = updated.avatarUrl
                }
            } catch {
                print("Failed to update profile: \(error)")
            }
        }
    }

    func uploadAvatar(imageData: Data) {
        // Always save locally so avatar persists across launches
        Self.saveLocalAvatar(imageData)
        currentUser.avatarUrl = Self.localAvatarURL?.absoluteString

        guard isOnline else { return }
        Task {
            do {
                let updated: APIUser = try await network.upload(
                    endpoint: "users/me/avatar",
                    imageData: imageData,
                    imageFieldName: "avatar",
                    fileName: "avatar.jpg",
                    mimeType: "image/jpeg"
                )
                await MainActor.run {
                    self.currentUser.avatarUrl = updated.avatarUrl
                }
            } catch {
                print("Failed to upload avatar: \(error)")
            }
        }
    }

    // MARK: - Local Avatar Persistence

    private static func localAvatarPath(for userId: UUID? = nil) -> URL {
        let id = userId ?? AuctionService.shared.currentUser.id
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("user_avatar_\(id.uuidString).jpg")
    }

    static var localAvatarURL: URL? {
        let path = localAvatarPath()
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
    }

    static func saveLocalAvatar(_ data: Data) {
        try? data.write(to: localAvatarPath())
    }

    static func loadLocalAvatarImage() -> UIImage? {
        guard let url = localAvatarURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    func refreshProfile() async {
        guard isOnline else { return }
        do {
            async let profileTask = network.fetchProfile()
            async let collectionsTask = network.fetchCollections()
            async let statsTask = network.fetchStats()

            let apiUser = try await profileTask
            let apiCollections = try await collectionsTask
            let stats = try await statsTask

            var user = Self.mapUserDTO(apiUser)
            user.collections = apiCollections.map { Self.mapCollectionDTO($0) }

            await MainActor.run {
                let previousOwned = self.currentUser.ownedArtworks
                self.currentUser = user
                self.userStats = stats
                // Restore locally-tracked ownedArtworks
                for artworkId in previousOwned where !self.currentUser.ownedArtworks.contains(artworkId) {
                    self.currentUser.ownedArtworks.append(artworkId)
                }
                // Compute from sold auctions
                let wonArtworkIds = self.auctions
                    .filter { $0.status == .sold && $0.winnerId == self.currentUser.id }
                    .map { $0.artwork.id }
                for artworkId in wonArtworkIds where !self.currentUser.ownedArtworks.contains(artworkId) {
                    self.currentUser.ownedArtworks.append(artworkId)
                }
            }
        } catch {
            print("Failed to refresh profile: \(error)")
        }
    }

    // MARK: - Bot Bidding (offline only)

    private func startBotBidding() {
        guard !isOnline else { return }

        botBidTimer?.invalidate()

        botBidTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { [weak self] _ in
            self?.simulateBotBid()
        }
    }

    private func simulateBotBid() {
        let activeAuctions = auctions.enumerated().filter { $0.element.isActive }
        guard !activeAuctions.isEmpty, Double.random(in: 0...1) < 0.3 else { return }

        guard let randomPick = activeAuctions.randomElement(),
              let bidder = Self.mockBotBidders.randomElement() else { return }
        let increment = Double.random(in: 0.01...max(randomPick.element.currentBid * 0.1, 0.05))
        let bidAmount = randomPick.element.currentBid + increment

        let bid = Bid(id: UUID(), userId: bidder.1, userName: bidder.0, amount: bidAmount, timestamp: Date())
        auctions[randomPick.offset].bids.append(bid)
        auctions[randomPick.offset].currentBid = bidAmount

        addNotification(title: L10n.newBid, message: L10n.newBidNotif(bidder.0, bid.formattedAmount, randomPick.element.artwork.title), type: .newBid)
    }

    // MARK: - User Actions

    func placeBid(on auctionId: UUID, amount: Double) -> BidResult {
        guard let index = auctions.firstIndex(where: { $0.id == auctionId }) else { return .failure(L10n.auctionNotFound) }
        let auction = auctions[index]
        guard auction.isActive else { return .failure(L10n.auctionNoLongerActive) }
        guard amount >= auction.minimumNextBid else { return .failure(L10n.bidMinimumError(String(format: "%.2f", auction.minimumNextBid))) }
        guard amount <= currentUser.balance else { return .failure(L10n.insufficientBalance) }

        analytics.trackBid(auctionId: auctionId.uuidString, amount: amount, artworkTitle: auction.artwork.title)
        MetricsService.shared.trackBidPlaced(amount: amount, auctionId: auctionId.uuidString)

        if isOnline {
            // Optimistic local update (rolled back on server-side rejection).
            let optimisticBid = Bid(id: UUID(), userId: currentUser.id, userName: currentUser.displayName, amount: amount, timestamp: Date())
            let previousBid = auctions[index].currentBid
            auctions[index].bids.append(optimisticBid)
            auctions[index].currentBid = amount

            let artworkTitle = auction.artwork.title
            let optimisticBidId = optimisticBid.id
            Task {
                do {
                    let apiBid = try await network.placeBid(request: APIPlaceBidRequest(auctionId: auctionId.uuidString, amount: amount))
                    await MainActor.run {
                        self.addNotification(title: L10n.bidPlaced, message: L10n.bidPlacedNotif(String(format: "%.2f ETH", apiBid.amount), artworkTitle), type: .bidPlaced)
                    }
                } catch let apiError as APIError {
                    await MainActor.run {
                        switch apiError {
                        case .networkError:
                            // Network issue — keep optimistic bid + queue for retry on reconnect.
                            self.bidQueue.queueBid(auctionId: auctionId, amount: amount)
                            self.analytics.track(.bidFailed, parameters: ["error": apiError.localizedDescription, "queued": "true"])
                            self.addNotification(title: L10n.bidQueued, message: L10n.pendingSync, type: .bidPlaced)
                        default:
                            // Server rejected — roll back optimistic update.
                            if let i = self.auctions.firstIndex(where: { $0.id == auctionId }) {
                                self.auctions[i].bids.removeAll { $0.id == optimisticBidId }
                                self.auctions[i].currentBid = previousBid
                            }
                            self.analytics.track(.bidFailed, parameters: ["error": apiError.localizedDescription])
                            self.addNotification(title: L10n.bidFailed, message: apiError.errorDescription ?? "Unknown error", type: .bidPlaced)
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.bidQueue.queueBid(auctionId: auctionId, amount: amount)
                        self.addNotification(title: L10n.bidQueued, message: L10n.pendingSync, type: .bidPlaced)
                    }
                }
            }
            return .success(optimisticBid)
        } else {
            // Offline: local bid + queue for sync when back online
            let bid = Bid(id: UUID(), userId: currentUser.id, userName: currentUser.displayName, amount: amount, timestamp: Date())
            auctions[index].bids.append(bid)
            auctions[index].currentBid = amount
            bidQueue.queueBid(auctionId: auctionId, amount: amount)
            addNotification(title: L10n.bidQueued, message: L10n.bidQueuedNotif(bid.formattedAmount), type: .bidPlaced)
            return .success(bid)
        }
    }

    // MARK: - Buy Now

    func buyNow(auctionId: UUID) -> BidResult {
        guard let index = auctions.firstIndex(where: { $0.id == auctionId }) else { return .failure(L10n.auctionNotFound) }
        let auction = auctions[index]
        guard auction.isActive else { return .failure(L10n.auctionNoLongerActive) }
        guard let buyNowPrice = auction.buyNowPrice else { return .failure(L10n.buyNowUnavailable) }
        guard buyNowPrice <= currentUser.balance else { return .failure(L10n.insufficientBalance) }

        let bid = Bid(id: UUID(), userId: currentUser.id, userName: currentUser.displayName, amount: buyNowPrice, timestamp: Date())
        auctions[index].bids.append(bid)
        auctions[index].currentBid = buyNowPrice
        auctions[index].status = .sold
        auctions[index].winnerId = currentUser.id

        let artworkId = auctions[index].artwork.id
        if !currentUser.ownedArtworks.contains(artworkId) {
            currentUser.ownedArtworks.append(artworkId)
            if let defaultIdx = currentUser.collections.firstIndex(where: { $0.isDefault }) {
                currentUser.collections[defaultIdx].artworkIds.append(artworkId)
            }
            wonAuctions.append(auctions[index])
        }

        addNotification(title: L10n.buyNowSuccess, message: L10n.buyNowNotif(auction.artwork.title, String(format: "%.2f ETH", buyNowPrice)), type: .auctionWon)

        if isOnline {
            Task {
                do {
                    _ = try await network.buyNow(auctionId: auctionId.uuidString)
                } catch {
                    print("Buy-now API failed: \(error)")
                }
            }
        }

        return .success(bid)
    }

    // MARK: - Auto-Broker

    func setAutoBroker(auctionId: UUID, maxAmount: Double) {
        let userId = currentUser.id
        if autoBrokerSettings[userId] == nil {
            autoBrokerSettings[userId] = [:]
        }
        autoBrokerSettings[userId]?[auctionId] = maxAmount
        addNotification(title: L10n.autoBrokerTitle, message: L10n.autoBrokerSet(String(format: "%.2f ETH", maxAmount)), type: .bidPlaced)

        if isOnline {
            Task {
                do {
                    _ = try await network.setAutoBroker(auctionId: auctionId.uuidString, maxAmount: maxAmount)
                } catch {
                    print("Auto-broker API failed: \(error)")
                }
            }
        }
    }

    func removeAutoBroker(auctionId: UUID) {
        autoBrokerSettings[currentUser.id]?[auctionId] = nil
    }

    func isAutoBrokerActive(for auctionId: UUID) -> Bool {
        autoBrokerSettings[currentUser.id]?[auctionId] != nil
    }

    // MARK: - Completed Auctions

    func fetchCompletedAuctions() {
        if isOnline {
            Task {
                do {
                    let apiAuctions = try await network.fetchAuctions(status: "sold")
                    let artworks = try await network.fetchArtworks()
                    var cache: [String: NFTArtwork] = [:]
                    for apiArt in artworks {
                        cache[apiArt.id] = Self.mapArtworkDTO(apiArt)
                    }
                    var mapped: [Auction] = []
                    for apiAuction in apiAuctions {
                        if let artwork = cache[apiAuction.artworkId] {
                            mapped.append(Self.mapAuctionDTO(apiAuction, artwork: artwork))
                        }
                    }
                    await MainActor.run { self.completedAuctions = mapped }
                } catch {
                    print("Failed to fetch completed auctions: \(error)")
                    await MainActor.run {
                        self.completedAuctions = self.auctions.filter { $0.status == .sold || $0.status == .ended }
                    }
                }
            }
        } else {
            completedAuctions = auctions.filter { $0.status == .sold || $0.status == .ended }
        }
    }

    func toggleFavorite(artworkId: UUID) {
        if let idx = currentUser.favoritedArtworks.firstIndex(of: artworkId) {
            currentUser.favoritedArtworks.remove(at: idx)
        } else {
            currentUser.favoritedArtworks.append(artworkId)
        }
    }

    func isFavorited(_ artworkId: UUID) -> Bool {
        currentUser.favoritedArtworks.contains(artworkId)
    }

    // MARK: - Collections

    func createCollection(name: String, description: String) -> NFTCollection {
        let collection = NFTCollection(name: name, description: description)
        currentUser.collections.append(collection)
        if isOnline {
            let localId = collection.id
            Task {
                do {
                    let apiCollection = try await network.createCollection(request: APICreateCollectionRequest(name: name, description: description, isPrivate: false))
                    let serverId = UUID(uuidString: apiCollection.id) ?? localId
                    await MainActor.run {
                        if let idx = self.currentUser.collections.firstIndex(where: { $0.id == localId }) {
                            self.currentUser.collections[idx].id = serverId
                        }
                    }
                } catch {}
            }
        }
        return collection
    }

    func updateCollection(id: UUID, name: String, description: String) {
        if let idx = currentUser.collections.firstIndex(where: { $0.id == id }) {
            currentUser.collections[idx].name = name
            currentUser.collections[idx].description = description
            currentUser.collections[idx].updatedAt = Date()
            if isOnline {
                Task {
                    try? await network.request(
                        endpoint: "collections/\(id.uuidString)",
                        method: .put,
                        body: ["name": name, "description": description]
                    ) as APICollection
                }
            }
        }
    }

    func deleteCollection(id: UUID) {
        currentUser.collections.removeAll { $0.id == id && !$0.isDefault }
        if isOnline { Task { try? await network.deleteCollection(id: id.uuidString) } }
    }

    func addToCollection(collectionId: UUID, artworkId: UUID) {
        if let idx = currentUser.collections.firstIndex(where: { $0.id == collectionId }) {
            if !currentUser.collections[idx].artworkIds.contains(artworkId) {
                currentUser.collections[idx].artworkIds.append(artworkId)
                currentUser.collections[idx].updatedAt = Date()
                if isOnline {
                    Task {
                        do {
                            try await network.addToCollection(collectionId: collectionId.uuidString, artworkId: artworkId.uuidString)
                        } catch {
                            // Collection might not exist on server — create it and retry
                            let col = await MainActor.run { self.currentUser.collections.first(where: { $0.id == collectionId }) }
                            guard let col else { return }
                            do {
                                let apiCol = try await network.createCollection(request: APICreateCollectionRequest(name: col.name, description: col.description, isPrivate: false))
                                if let serverId = UUID(uuidString: apiCol.id) {
                                    await MainActor.run {
                                        if let i = self.currentUser.collections.firstIndex(where: { $0.id == collectionId }) {
                                            self.currentUser.collections[i].id = serverId
                                        }
                                    }
                                    try? await network.addToCollection(collectionId: serverId.uuidString, artworkId: artworkId.uuidString)
                                }
                            } catch {}
                        }
                    }
                }
            }
        }
    }

    func removeFromCollection(collectionId: UUID, artworkId: UUID) {
        if let idx = currentUser.collections.firstIndex(where: { $0.id == collectionId }) {
            currentUser.collections[idx].artworkIds.removeAll { $0 == artworkId }
            currentUser.collections[idx].updatedAt = Date()
            if isOnline { Task { try? await network.removeFromCollection(collectionId: collectionId.uuidString, artworkId: artworkId.uuidString) } }
        }
    }

    // MARK: - Create NFT

    func createNFTFromImage(image: UIImage, title: String, description: String, category: NFTArtwork.ArtworkCategory, startingPrice: Double, durationHours: Double, blockchain: NFTArtwork.BlockchainNetwork = .ethereum, buyNowPrice: Double? = nil) -> Auction {
        analytics.trackNFTCreated(title: title, category: category.rawValue, startingPrice: startingPrice)
        let imageData = image.jpegData(compressionQuality: 0.8)
        let complexityScore = NormalMapGenerator.calculateTextureMetric(from: image)
        let artwork = NFTArtwork(
            title: title, artistName: currentUser.displayName, description: description,
            imageName: "user_\(UUID().uuidString)", category: category,
            tokenId: String(format: "%04d", auctions.count + 1),
            contractAddress: "0x\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(40))",
            blockchain: blockchain, imageSource: .uploaded, localImageData: imageData,
            textureComplexityScore: complexityScore
        )
        let auction = Auction(
            id: UUID(), artwork: artwork, startTime: Date(),
            endTime: Date().addingTimeInterval(durationHours * 3600),
            currentBid: startingPrice, bids: [], status: .active,
            startingPrice: startingPrice, reservePrice: nil, creatorId: currentUser.id,
            buyNowPrice: buyNowPrice
        )
        auctions.insert(auction, at: 0)
        featuredAuctions = Array(auctions.prefix(3))
        addNotification(title: L10n.nftCreatedTitle, message: L10n.nftCreatedNotif(title), type: .nftCreated)
        return auction
    }

    func auction(for artworkId: UUID) -> Auction? { auctions.first { $0.artwork.id == artworkId } }
    func ownedArtworks() -> [NFTArtwork] { currentUser.ownedArtworks.compactMap { id in auctions.first { $0.artwork.id == id }?.artwork } }

    func loadBids(for auctionId: UUID) async {
        guard isOnline else { return }
        do {
            let apiBids = try await network.fetchBids(auctionId: auctionId.uuidString)
            let bids = apiBids.map { Self.mapBidDTO($0) }
            await MainActor.run {
                if let index = auctions.firstIndex(where: { $0.id == auctionId }) {
                    auctions[index].bids = bids
                }
            }
        } catch { print("Failed to load bids: \(error)") }
    }

    // MARK: - Notifications

    private func addNotification(title: String, message: String, type: AuctionNotification.NotificationType) {
        let notification = AuctionNotification(title: title, message: message, type: type)
        DispatchQueue.main.async { [weak self] in
            self?.notifications.insert(notification, at: 0)
            if let count = self?.notifications.count, count > 50 {
                self?.notifications = Array(self?.notifications.prefix(50) ?? [])
            }
        }
    }

    deinit { auctionTimer?.invalidate(); botBidTimer?.invalidate() }
}

// MARK: - Supporting Types

enum BidResult {
    case success(Bid)
    case failure(String)
}

struct AuctionNotification: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let type: NotificationType
    let timestamp = Date()

    enum NotificationType { case newBid, bidPlaced, auctionWon, auctionEnded, nftCreated }

    var iconName: String {
        switch type {
        case .newBid: return "arrow.up.circle.fill"
        case .bidPlaced: return "gavel.fill"
        case .auctionWon: return "trophy.fill"
        case .auctionEnded: return "clock.badge.checkmark.fill"
        case .nftCreated: return "plus.circle.fill"
        }
    }

    var iconColor: String {
        switch type {
        case .newBid: return "blue"
        case .bidPlaced: return "purple"
        case .auctionWon: return "yellow"
        case .auctionEnded: return "gray"
        case .nftCreated: return "green"
        }
    }
}
