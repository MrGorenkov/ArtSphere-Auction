import Foundation
import SwiftUI

final class MockDataService: ObservableObject {
    @Published var auctions: [Auction] = []
    @Published var featuredAuctions: [Auction] = []
    @Published var currentUser: User

    static let shared = MockDataService()

    private init() {
        self.currentUser = Self.generateMockUser()
        let allAuctions = Self.generateMockAuctions()
        self.auctions = allAuctions
        self.featuredAuctions = Array(allAuctions.prefix(3))
    }

    // MARK: - Mock User

    private static func generateMockUser() -> User {
        User(
            id: UUID(),
            username: "artcollector",
            displayName: "Alex G.",
            walletAddress: "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
            avatarName: nil,
            bio: "Digital art enthusiast & NFT collector",
            ownedArtworks: [],
            favoritedArtworks: []
        )
    }

    // MARK: - Mock Artworks

    // (title, artist, description, category, colors, assetName)
    private static let artworkData: [(String, String, String, NFTArtwork.ArtworkCategory, [Color], String)] = [
        ("Звёздная ночь", "Винсент ван Гог", "Масло на холсте, 1889. Вихрящееся ночное небо над деревней.", .digitalPainting, [.blue, .yellow, .indigo], "starry_night"),
        ("Подсолнухи", "Винсент ван Гог", "Серия натюрмортов, масло на холсте, 1888.", .digitalPainting, [.yellow, .orange, .green], "sunflowers"),
        ("Водяные лилии", "Клод Моне", "Импрессионистский садовый пейзаж, масло на холсте, 1906.", .abstract, [.green, .teal, .blue], "water_lilies"),
        ("Впечатление. Восход солнца", "Клод Моне", "Картина, давшая название импрессионизму, 1872.", .digitalPainting, [.orange, .blue, .gray], "impression_sunrise"),
        ("Поцелуй", "Густав Климт", "Шедевр золотого периода, масло и сусальное золото, 1907–1908.", .abstract, [.yellow, .orange, .brown], "the_kiss"),
        ("Крик", "Эдвард Мунк", "Икона экспрессионизма, масло и пастель, 1893.", .abstract, [.orange, .red, .blue], "the_scream"),
        ("Композиция VIII", "Василий Кандинский", "Абстрактная геометрическая композиция, масло на холсте, 1923.", .generativeArt, [.yellow, .blue, .red], "composition_viii"),
        ("Завтрак гребцов", "Пьер-Огюст Ренуар", "Масло на холсте, 1881. Сцена обеда на открытом воздухе.", .photography, [.orange, .white, .blue], "boating_party"),
        ("Гора Сент-Виктуар", "Поль Сезанн", "Постимпрессионистский пейзаж, масло на холсте, 1902.", .digitalPainting, [.green, .blue, .purple], "mont_sainte_victoire"),
        ("Большая волна", "Кацусика Хокусай", "Гравюра из серии «36 видов Фудзи», 1831.", .pixel, [.blue, .white, .indigo], "great_wave"),
        ("Digital Sunrise", "Amara Okafor", "Digital landscape capturing the first light.", .digitalPainting, [.orange, .yellow, .pink], ""),
        ("Quantum Bloom", "Leo Fischer", "Generative floral patterns from quantum distributions.", .generativeArt, [.pink, .purple, .white], ""),
    ]

    private static func generateMockArtworks() -> [NFTArtwork] {
        artworkData.enumerated().map { index, data in
            let hasBundled = !data.5.isEmpty
            return NFTArtwork(
                id: UUID(),
                title: data.0,
                artistName: data.1,
                description: data.2,
                imageName: hasBundled ? data.5 : "artwork_\(index)",
                category: data.3,
                createdAt: Date().addingTimeInterval(-Double(index) * 86400),
                tokenId: String(format: "%04d", index + 1),
                contractAddress: "0x\(String(repeating: "a", count: 40))",
                blockchain: index % 2 == 0 ? .ethereum : .polygon,
                imageSource: hasBundled ? .bundled : .procedural
            )
        }
    }

    // MARK: - Mock Auctions

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

            let hoursRemaining = Double.random(in: 1...72)
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

    // MARK: - Procedural Artwork Image Generation

    static func generateArtworkImage(for artwork: NFTArtwork, size: CGSize = CGSize(width: 400, height: 400)) -> UIImage {
        let colors = artworkColors(for: artwork)
        return generateProceduralImage(colors: colors, seed: artwork.id.hashValue, size: size)
    }

    private static func artworkColors(for artwork: NFTArtwork) -> [Color] {
        if let index = artworkData.firstIndex(where: { $0.0 == artwork.title }) {
            return artworkData[index].4
        }
        return [.purple, .blue]
    }

    /// Returns bundled UIImage for the artwork, if available
    static func bundledImage(for artwork: NFTArtwork) -> UIImage? {
        guard artwork.imageSource == .bundled else { return nil }
        return UIImage(named: artwork.imageName)
    }

    private static func generateProceduralImage(colors: [Color], seed: Int, size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let ctx = context.cgContext

            // Background gradient
            let uiColors = colors.map { UIColor($0) }
            let cgColors = uiColors.map { $0.cgColor }
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                          colors: cgColors as CFArray,
                                          locations: nil) {
                ctx.drawLinearGradient(gradient,
                                       start: CGPoint(x: 0, y: 0),
                                       end: CGPoint(x: size.width, y: size.height),
                                       options: [])
            }

            // Procedural shapes based on seed
            var rng = SeededRNG(seed: seed)

            // Circles
            for _ in 0..<Int.random(in: 5...15, using: &rng) {
                let radius = CGFloat.random(in: 20...120, using: &rng)
                let x = CGFloat.random(in: -radius...size.width, using: &rng)
                let y = CGFloat.random(in: -radius...size.height, using: &rng)
                let alpha = CGFloat.random(in: 0.05...0.3, using: &rng)

                let colorIndex = Int.random(in: 0..<uiColors.count, using: &rng)
                ctx.setFillColor(uiColors[colorIndex].withAlphaComponent(alpha).cgColor)
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: radius * 2, height: radius * 2))
            }

            // Lines
            for _ in 0..<Int.random(in: 3...8, using: &rng) {
                let lineWidth = CGFloat.random(in: 1...4, using: &rng)
                ctx.setLineWidth(lineWidth)
                let alpha = CGFloat.random(in: 0.1...0.5, using: &rng)
                let colorIndex = Int.random(in: 0..<uiColors.count, using: &rng)
                ctx.setStrokeColor(uiColors[colorIndex].withAlphaComponent(alpha).cgColor)
                ctx.move(to: CGPoint(
                    x: CGFloat.random(in: 0...size.width, using: &rng),
                    y: CGFloat.random(in: 0...size.height, using: &rng)
                ))
                ctx.addLine(to: CGPoint(
                    x: CGFloat.random(in: 0...size.width, using: &rng),
                    y: CGFloat.random(in: 0...size.height, using: &rng)
                ))
                ctx.strokePath()
            }

            // Rounded rects
            for _ in 0..<Int.random(in: 2...6, using: &rng) {
                let w = CGFloat.random(in: 30...150, using: &rng)
                let h = CGFloat.random(in: 30...150, using: &rng)
                let x = CGFloat.random(in: 0...size.width - w, using: &rng)
                let y = CGFloat.random(in: 0...size.height - h, using: &rng)
                let alpha = CGFloat.random(in: 0.05...0.25, using: &rng)
                let colorIndex = Int.random(in: 0..<uiColors.count, using: &rng)

                let path = UIBezierPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: 8)
                ctx.setFillColor(uiColors[colorIndex].withAlphaComponent(alpha).cgColor)
                ctx.addPath(path.cgPath)
                ctx.fillPath()
            }

            // Noise overlay
            for x in stride(from: 0, to: Int(size.width), by: 4) {
                for y in stride(from: 0, to: Int(size.height), by: 4) {
                    let noise = CGFloat.random(in: 0...1, using: &rng)
                    if noise > 0.97 {
                        ctx.setFillColor(UIColor.white.withAlphaComponent(0.08).cgColor)
                        ctx.fill(CGRect(x: x, y: y, width: 2, height: 2))
                    }
                }
            }
        }
    }
}

// MARK: - Seeded Random Number Generator

struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: Int) {
        self.state = UInt64(bitPattern: Int64(seed))
        if self.state == 0 { self.state = 1 }
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
