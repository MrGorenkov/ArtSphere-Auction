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
        self.currentUser = Self.generateMockUser()

        webSocket.$latestBidUpdate
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                self?.handleWSBidUpdate(update)
            }
            .store(in: &cancellables)

        webSocket.$latestAuctionUpdate
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                self?.handleWSAuctionUpdate(update)
            }
            .store(in: &cancellables)

        webSocket.$latestUserNotification
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleWSUserNotification(notification)
            }
            .store(in: &cancellables)

        startAuctionMonitoring()
    }

    // MARK: - Load from API

    func loadFromAPI() async {
        await MainActor.run { isLoadingFromAPI = true }

        do {
            let styles = try await network.fetchStyles()
            await MainActor.run { artStyles = styles }

            async let artworksTask = network.fetchArtworks()
            async let auctionsTask = network.fetchAuctions(status: "active")

            let apiArtworks = try await artworksTask
            let apiAuctions = try await auctionsTask

            var cache: [String: NFTArtwork] = [:]
            for apiArt in apiArtworks {
                let artwork = Self.mapArtwork(apiArt)
                cache[apiArt.id] = artwork
            }

            var mappedAuctions: [Auction] = []
            for apiAuction in apiAuctions {
                if let artwork = cache[apiAuction.artworkId] {
                    let auction = Self.mapAuction(apiAuction, artwork: artwork)
                    mappedAuctions.append(auction)
                }
            }

            if network.authToken != nil {
                do {
                    let apiUser = try await network.fetchProfile()
                    let user = Self.mapUser(apiUser)

                    let apiCollections = try await network.fetchCollections()
                    var mappedUser = user
                    mappedUser.collections = apiCollections.map { Self.mapCollection($0) }

                    await MainActor.run {
                        self.currentUser = mappedUser
                    }

                    webSocket.subscribeToUser(apiUser.id)
                } catch {
                    print("Profile load failed: \(error)")
                }
            }

            await MainActor.run {
                self.artworkCache = cache
                self.auctions = mappedAuctions
                self.featuredAuctions = Array(mappedAuctions.prefix(3))
                self.isOnline = true
                self.isLoadingFromAPI = false
            }

            // Subscribe to global auction feed via WebSocket
            webSocket.subscribeToAuctionFeed()

            // Sync any queued offline bids
            if bidQueue.hasPendingBids {
                bidQueue.syncQueue()
            }

        } catch {
            print("API load failed, using local data: \(error)")
            await MainActor.run {
                self.isOnline = false
                self.isLoadingFromAPI = false
            }
            await loadLocalData()
        }
    }

    private func loadLocalData() async {
        let allAuctions = Self.generateMockAuctions()
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

    // MARK: - DTO Mapping

    static func mapArtwork(_ api: APIArtwork) -> NFTArtwork {
        let category = mapStyleToCategory(api.styleName)
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

    static func mapAuction(_ api: APIAuction, artwork: NFTArtwork) -> Auction {
        let formatter = ISO8601DateFormatter()
        let status: Auction.AuctionStatus
        switch api.status {
        case "active": status = .active
        case "upcoming": status = .upcoming
        case "sold": status = .sold
        default: status = .ended
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
            serverBidCount: api.bidCount
        )
    }

    static func mapBid(_ api: APIBid) -> Bid {
        Bid(
            id: UUID(uuidString: api.id) ?? UUID(),
            userId: UUID(uuidString: api.userId) ?? UUID(),
            userName: api.userName,
            amount: api.amount,
            timestamp: ISO8601DateFormatter().date(from: api.timestamp) ?? Date()
        )
    }

    static func mapUser(_ api: APIUser) -> User {
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

    static func mapCollection(_ api: APICollection) -> NFTCollection {
        NFTCollection(
            id: UUID(uuidString: api.id) ?? UUID(),
            name: api.name,
            description: api.description ?? "",
            artworkIds: api.artworkIds.compactMap { UUID(uuidString: $0) },
            isDefault: api.isDefault
        )
    }

    static func mapStyleToCategory(_ styleName: String?) -> NFTArtwork.ArtworkCategory {
        guard let name = styleName?.lowercased() else { return .digitalPainting }
        if name.contains("генеративн") || name.contains("generativ") { return .generativeArt }
        if name.contains("фото") || name.contains("photo") { return .photography }
        if name.contains("абстракц") || name.contains("abstract") { return .abstract }
        if name.contains("пиксел") || name.contains("pixel") { return .pixel }
        if name.contains("3d") || name.contains("3д") { return .threeD }
        return .digitalPainting
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
                    addNotification(title: "Auction Won!", message: "You won \"\(auctions[index].artwork.title)\" for \(highestBid.formattedAmount)!", type: .auctionWon)
                }
            } else {
                addNotification(title: "Auction Ended", message: "\"\(auctions[index].artwork.title)\" was sold to \(highestBid.userName)", type: .auctionEnded)
            }
        } else {
            auctions[index].status = .ended
            addNotification(title: "Auction Ended", message: "\"\(auctions[index].artwork.title)\" received no bids", type: .auctionEnded)
        }
    }

    // MARK: - WebSocket Handlers

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
            addNotification(title: "New Bid", message: "\(bid.userName) bid \(bid.formattedAmount) on \"\(auctions[index].artwork.title)\"", type: .newBid)
        }
    }

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
                let mappedBids = apiBids.map { Self.mapBid($0) }
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

    private static var localAvatarPath: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("user_avatar.jpg")
    }

    static var localAvatarURL: URL? {
        FileManager.default.fileExists(atPath: localAvatarPath.path) ? localAvatarPath : nil
    }

    static func saveLocalAvatar(_ data: Data) {
        try? data.write(to: localAvatarPath)
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

            var user = Self.mapUser(apiUser)
            user.collections = apiCollections.map { Self.mapCollection($0) }

            await MainActor.run {
                self.currentUser = user
                self.userStats = stats
            }
        } catch {
            print("Failed to refresh profile: \(error)")
        }
    }

    // MARK: - Bot Bidding (offline only)

    private let botBidders: [(String, UUID)] = [
        ("CryptoWhale", UUID()), ("ArtLover42", UUID()), ("NFTHunter", UUID()),
        ("DigitalDragon", UUID()), ("BlockBuster", UUID()), ("PixelPioneer", UUID()), ("ChainChaser", UUID()),
    ]

    private func startBotBidding() {
        guard !isOnline else { return }
        botBidTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { [weak self] _ in
            self?.simulateBotBid()
        }
    }

    private func simulateBotBid() {
        let activeAuctions = auctions.enumerated().filter { $0.element.isActive }
        guard !activeAuctions.isEmpty, Double.random(in: 0...1) < 0.3 else { return }

        let randomPick = activeAuctions.randomElement()!
        let bidder = botBidders.randomElement()!
        let increment = Double.random(in: 0.01...max(randomPick.element.currentBid * 0.1, 0.05))
        let bidAmount = randomPick.element.currentBid + increment

        let bid = Bid(id: UUID(), userId: bidder.1, userName: bidder.0, amount: bidAmount, timestamp: Date())
        auctions[randomPick.offset].bids.append(bid)
        auctions[randomPick.offset].currentBid = bidAmount

        addNotification(title: "New Bid", message: "\(bidder.0) bid \(bid.formattedAmount) on \"\(randomPick.element.artwork.title)\"", type: .newBid)
    }

    // MARK: - User Actions

    func placeBid(on auctionId: UUID, amount: Double) -> BidResult {
        guard let index = auctions.firstIndex(where: { $0.id == auctionId }) else { return .failure("Auction not found") }
        let auction = auctions[index]
        guard auction.isActive else { return .failure("Auction is no longer active") }
        guard amount >= auction.minimumNextBid else { return .failure("Bid must be at least \(String(format: "%.2f", auction.minimumNextBid)) ETH") }
        guard amount <= currentUser.balance else { return .failure("Insufficient balance") }

        analytics.trackBid(auctionId: auctionId.uuidString, amount: amount, artworkTitle: auction.artwork.title)

        if isOnline {
            // When online, send to API — the WS feed will broadcast the update back
            let artworkTitle = auction.artwork.title
            Task {
                do {
                    let apiBid = try await network.placeBid(request: APIPlaceBidRequest(auctionId: auctionId.uuidString, amount: amount))
                    await MainActor.run {
                        self.addNotification(title: "Bid Placed", message: "You bid \(String(format: "%.2f ETH", apiBid.amount)) on \"\(artworkTitle)\"", type: .bidPlaced)
                    }
                } catch let apiError as APIError {
                    await MainActor.run {
                        switch apiError {
                        case .networkError:
                            // Network issue — queue for retry on reconnect
                            self.bidQueue.queueBid(auctionId: auctionId, amount: amount)
                            self.analytics.track(.bidFailed, parameters: ["error": apiError.localizedDescription, "queued": "true"])
                            self.addNotification(title: L10n.bidQueued, message: L10n.pendingSync, type: .bidPlaced)
                        default:
                            // Server error (400, 404 etc.) — show actual error
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
            // Optimistic local update for immediate UI feedback
            let bid = Bid(id: UUID(), userId: currentUser.id, userName: currentUser.displayName, amount: amount, timestamp: Date())
            auctions[index].bids.append(bid)
            auctions[index].currentBid = amount
            return .success(bid)
        } else {
            // Offline: local bid + queue for sync when back online
            let bid = Bid(id: UUID(), userId: currentUser.id, userName: currentUser.displayName, amount: amount, timestamp: Date())
            auctions[index].bids.append(bid)
            auctions[index].currentBid = amount
            bidQueue.queueBid(auctionId: auctionId, amount: amount)
            addNotification(title: "Bid Queued", message: "You bid \(bid.formattedAmount) — will sync when online", type: .bidPlaced)
            return .success(bid)
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
            Task { try? await network.createCollection(request: APICreateCollectionRequest(name: name, description: description, isPrivate: false)) }
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
                if isOnline { Task { try? await network.addToCollection(collectionId: collectionId.uuidString, artworkId: artworkId.uuidString) } }
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

    func createNFTFromImage(image: UIImage, title: String, description: String, category: NFTArtwork.ArtworkCategory, startingPrice: Double, durationHours: Double) -> Auction {
        analytics.trackNFTCreated(title: title, category: category.rawValue, startingPrice: startingPrice)
        let imageData = image.jpegData(compressionQuality: 0.8)
        let artwork = NFTArtwork(
            title: title, artistName: currentUser.displayName, description: description,
            imageName: "user_\(UUID().uuidString)", category: category,
            tokenId: String(format: "%04d", auctions.count + 1),
            contractAddress: "0x\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(40))",
            blockchain: .polygon, imageSource: .uploaded, localImageData: imageData
        )
        let auction = Auction(
            id: UUID(), artwork: artwork, startTime: Date(),
            endTime: Date().addingTimeInterval(durationHours * 3600),
            currentBid: startingPrice, bids: [], status: .active,
            startingPrice: startingPrice, reservePrice: nil, creatorId: currentUser.id
        )
        auctions.insert(auction, at: 0)
        featuredAuctions = Array(auctions.prefix(3))
        addNotification(title: "NFT Created", message: "Your artwork \"\(title)\" is now live!", type: .nftCreated)
        return auction
    }

    func auction(for artworkId: UUID) -> Auction? { auctions.first { $0.artwork.id == artworkId } }
    func ownedArtworks() -> [NFTArtwork] { currentUser.ownedArtworks.compactMap { id in auctions.first { $0.artwork.id == id }?.artwork } }

    func loadBids(for auctionId: UUID) async {
        guard isOnline else { return }
        do {
            let apiBids = try await network.fetchBids(auctionId: auctionId.uuidString)
            let bids = apiBids.map { Self.mapBid($0) }
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

    // MARK: - Mock Data (offline fallback)

    private static func generateMockUser() -> User {
        User(username: "artcollector", displayName: "Alex G.", walletAddress: "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D", bio: "Digital art enthusiast & NFT collector", balance: 25.0)
    }

    private static let artworkData: [(String, String, String, NFTArtwork.ArtworkCategory)] = [
        ("Cosmic Dreams", "Elena Vasquez", "A mesmerizing journey through digital cosmos.", .digitalPainting),
        ("Neural Garden", "Kai Tanaka", "Generated by a custom neural network.", .generativeArt),
        ("Neon District", "Marcus Chen", "Cyberpunk-inspired urban landscape.", .photography),
        ("Ethereal Flow", "Sofia Andersen", "Abstract representation of blockchain data flows.", .abstract),
        ("Pixel Samurai", "Yuki Mori", "A tribute to Japanese warrior culture in pixel art.", .pixel),
        ("Crystal Matrix", "David Park", "3D crystalline structures inspired by molecular geometry.", .threeD),
        ("Digital Sunrise", "Amara Okafor", "Digital landscape capturing the first light.", .digitalPainting),
        ("Quantum Bloom", "Leo Fischer", "Generative floral patterns from quantum distributions.", .generativeArt),
        ("Urban Reflections", "Nina Volkov", "Street photography reimagined through fractals.", .photography),
        ("Void Walker", "Rex Sterling", "Abstract exploration of negative space.", .abstract),
        ("Crypto Cats", "Mia Zhang", "Playful pixel art collection.", .pixel),
        ("Holographic Temple", "Arjun Patel", "Sacred architecture as holographic 3D.", .threeD),
    ]

    private static func generateMockAuctions() -> [Auction] {
        let artworks = generateMockArtworks()
        let bidders = [("CryptoWhale", UUID()), ("ArtLover42", UUID()), ("NFTHunter", UUID()), ("DigitalDragon", UUID()), ("BlockBuster", UUID())]
        return artworks.enumerated().map { index, artwork in
            let startingPrice = Double.random(in: 0.1...5.0)
            let bidCount = Int.random(in: 0...8)
            var currentBid = startingPrice
            var bids: [Bid] = []
            for i in 0..<bidCount {
                currentBid += Double.random(in: 0.05...0.5)
                let bidder = bidders[i % bidders.count]
                bids.append(Bid(id: UUID(), userId: bidder.1, userName: bidder.0, amount: currentBid, timestamp: Date().addingTimeInterval(-Double(bidCount - i) * 3600)))
            }
            let hoursRemaining = index < 2 ? Double.random(in: 0.03...0.08) : Double.random(in: 1...72)
            return Auction(id: UUID(), artwork: artwork, startTime: Date().addingTimeInterval(-Double.random(in: 3600...86400)), endTime: Date().addingTimeInterval(hoursRemaining * 3600), currentBid: currentBid, bids: bids, status: index < 10 ? .active : .upcoming, startingPrice: startingPrice, reservePrice: startingPrice * 2)
        }
    }

    private static func generateMockArtworks() -> [NFTArtwork] {
        artworkData.enumerated().map { index, data in
            NFTArtwork(title: data.0, artistName: data.1, description: data.2, imageName: "artwork_\(index)", category: data.3, createdAt: Date().addingTimeInterval(-Double(index) * 86400), tokenId: String(format: "%04d", index + 1), contractAddress: "0x\(String(repeating: "a", count: 40))", blockchain: index % 2 == 0 ? .ethereum : .polygon)
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
