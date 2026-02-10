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

    private var auctionTimer: Timer?
    private var botBidTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // Simulated bot bidders
    private let botBidders: [(String, UUID)] = [
        ("CryptoWhale", UUID()),
        ("ArtLover42", UUID()),
        ("NFTHunter", UUID()),
        ("DigitalDragon", UUID()),
        ("BlockBuster", UUID()),
        ("PixelPioneer", UUID()),
        ("ChainChaser", UUID()),
    ]

    private init() {
        self.currentUser = Self.generateMockUser()
        let allAuctions = Self.generateMockAuctions()
        self.auctions = allAuctions
        self.featuredAuctions = Array(allAuctions.prefix(3))

        // Default collection
        let defaultCollection = NFTCollection(
            name: "My NFTs",
            description: "All collected artworks",
            isDefault: true
        )
        self.currentUser.collections = [defaultCollection]

        startAuctionMonitoring()
        startBotBidding()
    }

    // MARK: - Real-Time Auction Monitoring

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
        if updated {
            objectWillChange.send()
        }
    }

    private func finalizeAuction(at index: Int) {
        guard index < auctions.count else { return }

        if let highestBid = auctions[index].highestBid {
            auctions[index].status = .sold
            auctions[index].winnerId = highestBid.userId

            // Check if current user won
            if highestBid.userId == currentUser.id {
                let artworkId = auctions[index].artwork.id
                if !currentUser.ownedArtworks.contains(artworkId) {
                    currentUser.ownedArtworks.append(artworkId)

                    // Add to default collection
                    if let defaultIdx = currentUser.collections.firstIndex(where: { $0.isDefault }) {
                        currentUser.collections[defaultIdx].artworkIds.append(artworkId)
                    }

                    wonAuctions.append(auctions[index])

                    addNotification(
                        title: "Auction Won!",
                        message: "You won \"\(auctions[index].artwork.title)\" for \(highestBid.formattedAmount)!",
                        type: .auctionWon
                    )
                }
            } else {
                // Bot won
                addNotification(
                    title: "Auction Ended",
                    message: "\"\(auctions[index].artwork.title)\" was sold to \(highestBid.userName)",
                    type: .auctionEnded
                )
            }
        } else {
            auctions[index].status = .ended
            addNotification(
                title: "Auction Ended",
                message: "\"\(auctions[index].artwork.title)\" received no bids",
                type: .auctionEnded
            )
        }
    }

    // MARK: - Bot Bidding Simulation

    private func startBotBidding() {
        botBidTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { [weak self] _ in
            self?.simulateBotBid()
        }
    }

    private func simulateBotBid() {
        let activeAuctions = auctions.enumerated().filter { $0.element.isActive }
        guard !activeAuctions.isEmpty else { return }

        // Pick a random active auction (30% chance per tick)
        guard Double.random(in: 0...1) < 0.3 else { return }

        let randomPick = activeAuctions.randomElement()!
        let auctionIndex = randomPick.offset
        let auction = randomPick.element

        let bidder = botBidders.randomElement()!
        let increment = Double.random(in: 0.01...max(auction.currentBid * 0.1, 0.05))
        let bidAmount = auction.currentBid + increment

        let bid = Bid(
            id: UUID(),
            userId: bidder.1,
            userName: bidder.0,
            amount: bidAmount,
            timestamp: Date()
        )

        auctions[auctionIndex].bids.append(bid)
        auctions[auctionIndex].currentBid = bidAmount

        addNotification(
            title: "New Bid",
            message: "\(bidder.0) bid \(bid.formattedAmount) on \"\(auction.artwork.title)\"",
            type: .newBid
        )
    }

    // MARK: - User Actions

    func placeBid(on auctionId: UUID, amount: Double) -> BidResult {
        guard let index = auctions.firstIndex(where: { $0.id == auctionId }) else {
            return .failure("Auction not found")
        }

        let auction = auctions[index]

        guard auction.isActive else {
            return .failure("Auction is no longer active")
        }

        guard amount >= auction.minimumNextBid else {
            return .failure("Bid must be at least \(String(format: "%.2f", auction.minimumNextBid)) ETH")
        }

        guard amount <= currentUser.balance else {
            return .failure("Insufficient balance. You have \(currentUser.formattedBalance)")
        }

        let bid = Bid(
            id: UUID(),
            userId: currentUser.id,
            userName: currentUser.displayName,
            amount: amount,
            timestamp: Date()
        )

        auctions[index].bids.append(bid)
        auctions[index].currentBid = amount

        addNotification(
            title: "Bid Placed",
            message: "You bid \(bid.formattedAmount) on \"\(auction.artwork.title)\"",
            type: .bidPlaced
        )

        return .success(bid)
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

    // MARK: - Collection Management

    func createCollection(name: String, description: String) -> NFTCollection {
        let collection = NFTCollection(name: name, description: description)
        currentUser.collections.append(collection)
        return collection
    }

    func updateCollection(id: UUID, name: String, description: String) {
        if let idx = currentUser.collections.firstIndex(where: { $0.id == id }) {
            currentUser.collections[idx].name = name
            currentUser.collections[idx].description = description
            currentUser.collections[idx].updatedAt = Date()
        }
    }

    func deleteCollection(id: UUID) {
        currentUser.collections.removeAll { $0.id == id && !$0.isDefault }
    }

    func addToCollection(collectionId: UUID, artworkId: UUID) {
        if let idx = currentUser.collections.firstIndex(where: { $0.id == collectionId }) {
            if !currentUser.collections[idx].artworkIds.contains(artworkId) {
                currentUser.collections[idx].artworkIds.append(artworkId)
                currentUser.collections[idx].updatedAt = Date()
            }
        }
    }

    func removeFromCollection(collectionId: UUID, artworkId: UUID) {
        if let idx = currentUser.collections.firstIndex(where: { $0.id == collectionId }) {
            currentUser.collections[idx].artworkIds.removeAll { $0 == artworkId }
            currentUser.collections[idx].updatedAt = Date()
        }
    }

    // MARK: - Create NFT from uploaded image

    func createNFTFromImage(
        image: UIImage,
        title: String,
        description: String,
        category: NFTArtwork.ArtworkCategory,
        startingPrice: Double,
        durationHours: Double
    ) -> Auction {
        let imageData = image.jpegData(compressionQuality: 0.8)

        let artwork = NFTArtwork(
            title: title,
            artistName: currentUser.displayName,
            description: description,
            imageName: "user_\(UUID().uuidString)",
            category: category,
            tokenId: String(format: "%04d", auctions.count + 1),
            contractAddress: "0x\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(40))",
            blockchain: .polygon,
            imageSource: .uploaded,
            localImageData: imageData
        )

        let auction = Auction(
            id: UUID(),
            artwork: artwork,
            startTime: Date(),
            endTime: Date().addingTimeInterval(durationHours * 3600),
            currentBid: startingPrice,
            bids: [],
            status: .active,
            startingPrice: startingPrice,
            reservePrice: nil,
            creatorId: currentUser.id
        )

        auctions.insert(auction, at: 0)
        featuredAuctions = Array(auctions.prefix(3))

        addNotification(
            title: "NFT Created",
            message: "Your artwork \"\(title)\" is now live on auction!",
            type: .nftCreated
        )

        return auction
    }

    // MARK: - Artwork Lookup

    func auction(for artworkId: UUID) -> Auction? {
        auctions.first { $0.artwork.id == artworkId }
    }

    func ownedArtworks() -> [NFTArtwork] {
        currentUser.ownedArtworks.compactMap { artworkId in
            auctions.first { $0.artwork.id == artworkId }?.artwork
        }
    }

    // MARK: - Notifications

    private func addNotification(title: String, message: String, type: AuctionNotification.NotificationType) {
        let notification = AuctionNotification(
            title: title,
            message: message,
            type: type
        )
        DispatchQueue.main.async { [weak self] in
            self?.notifications.insert(notification, at: 0)
            // Keep last 50 notifications
            if let count = self?.notifications.count, count > 50 {
                self?.notifications = Array(self?.notifications.prefix(50) ?? [])
            }
        }
    }

    // MARK: - Mock Data Generation

    private static func generateMockUser() -> User {
        User(
            username: "artcollector",
            displayName: "Alex G.",
            walletAddress: "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
            bio: "Digital art enthusiast & NFT collector",
            balance: 10.0
        )
    }

    private static let artworkData: [(String, String, String, NFTArtwork.ArtworkCategory)] = [
        ("Cosmic Dreams", "Elena Vasquez", "A mesmerizing journey through digital cosmos, blending vibrant nebulae with abstract geometric forms.", .digitalPainting),
        ("Neural Garden", "Kai Tanaka", "Generated by a custom neural network trained on botanical illustrations from the 18th century.", .generativeArt),
        ("Neon District", "Marcus Chen", "Cyberpunk-inspired urban landscape captured through the lens of AI-enhanced photography.", .photography),
        ("Ethereal Flow", "Sofia Andersen", "Abstract representation of blockchain data flows, visualized as luminous streams of energy.", .abstract),
        ("Pixel Samurai", "Yuki Mori", "A tribute to Japanese warrior culture rendered in a retro 32-bit pixel art style.", .pixel),
        ("Crystal Matrix", "David Park", "3D-rendered crystalline structures inspired by molecular geometry and sacred patterns.", .threeD),
        ("Digital Sunrise", "Amara Okafor", "Breathtaking digital landscape capturing the first light over a futuristic cityscape.", .digitalPainting),
        ("Quantum Bloom", "Leo Fischer", "Generative floral patterns emerging from quantum probability distributions.", .generativeArt),
        ("Urban Reflections", "Nina Volkov", "Street photography reimagined through fractal mirror algorithms.", .photography),
        ("Void Walker", "Rex Sterling", "Abstract exploration of negative space and dimensional boundaries.", .abstract),
        ("Crypto Cats", "Mia Zhang", "Playful pixel art collection celebrating the intersection of cats and cryptography.", .pixel),
        ("Holographic Temple", "Arjun Patel", "Sacred architecture reconstructed as a holographic 3D environment.", .threeD),
    ]

    private static func generateMockAuctions() -> [Auction] {
        let artworks = generateMockArtworks()
        let bidders = [
            ("CryptoWhale", UUID()),
            ("ArtLover42", UUID()),
            ("NFTHunter", UUID()),
            ("DigitalDragon", UUID()),
            ("BlockBuster", UUID()),
        ]

        return artworks.enumerated().map { index, artwork in
            let startingPrice = Double.random(in: 0.1...5.0)
            let bidCount = Int.random(in: 0...8)
            var currentBid = startingPrice
            var bids: [Bid] = []

            for i in 0..<bidCount {
                let increment = Double.random(in: 0.05...0.5)
                currentBid += increment
                let bidder = bidders[i % bidders.count]
                bids.append(Bid(
                    id: UUID(),
                    userId: bidder.1,
                    userName: bidder.0,
                    amount: currentBid,
                    timestamp: Date().addingTimeInterval(-Double(bidCount - i) * 3600)
                ))
            }

            // Mix of short and long auctions for testing
            let hoursRemaining: Double
            if index < 2 {
                // Short auctions (2-5 minutes) for testing auction end
                hoursRemaining = Double.random(in: 0.03...0.08)
            } else {
                hoursRemaining = Double.random(in: 1...72)
            }

            let status: Auction.AuctionStatus = index < 10 ? .active : .upcoming

            return Auction(
                id: UUID(),
                artwork: artwork,
                startTime: Date().addingTimeInterval(-Double.random(in: 3600...86400)),
                endTime: Date().addingTimeInterval(hoursRemaining * 3600),
                currentBid: currentBid,
                bids: bids,
                status: status,
                startingPrice: startingPrice,
                reservePrice: startingPrice * 2
            )
        }
    }

    private static func generateMockArtworks() -> [NFTArtwork] {
        artworkData.enumerated().map { index, data in
            NFTArtwork(
                title: data.0,
                artistName: data.1,
                description: data.2,
                imageName: "artwork_\(index)",
                category: data.3,
                createdAt: Date().addingTimeInterval(-Double(index) * 86400),
                tokenId: String(format: "%04d", index + 1),
                contractAddress: "0x\(String(repeating: "a", count: 40))",
                blockchain: index % 2 == 0 ? .ethereum : .polygon
            )
        }
    }

    deinit {
        auctionTimer?.invalidate()
        botBidTimer?.invalidate()
    }
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

    enum NotificationType {
        case newBid
        case bidPlaced
        case auctionWon
        case auctionEnded
        case nftCreated
    }

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
