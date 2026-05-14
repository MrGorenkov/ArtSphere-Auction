import Foundation

/// Offline / preview-only seed data and bot-bidder identities. Used when the API is
/// unreachable so the UI still has something to render.
extension AuctionService {

    static let mockBotBidders: [(String, UUID)] = [
        ("CryptoWhale", UUID()),
        ("ArtLover42", UUID()),
        ("NFTHunter", UUID()),
        ("DigitalDragon", UUID()),
        ("BlockBuster", UUID()),
        ("PixelPioneer", UUID()),
        ("ChainChaser", UUID()),
    ]

    /// (title, artist, description, category, assetName or "" for procedural)
    static let mockArtworkData: [(String, String, String, NFTArtwork.ArtworkCategory, String)] = [
        ("Звёздная ночь", "Винсент ван Гог", "Масло на холсте, 1889. Вихрящееся ночное небо над деревней.", .digitalPainting, "starry_night"),
        ("Подсолнухи", "Винсент ван Гог", "Серия натюрмортов, масло на холсте, 1888.", .digitalPainting, "sunflowers"),
        ("Водяные лилии", "Клод Моне", "Импрессионистский садовый пейзаж, масло на холсте, 1906.", .abstract, "water_lilies"),
        ("Впечатление. Восход солнца", "Клод Моне", "Картина, давшая название импрессионизму, 1872.", .digitalPainting, "impression_sunrise"),
        ("Поцелуй", "Густав Климт", "Шедевр золотого периода, масло и сусальное золото, 1907–1908.", .abstract, "the_kiss"),
        ("Крик", "Эдвард Мунк", "Икона экспрессионизма, масло и пастель, 1893.", .abstract, "the_scream"),
        ("Композиция VIII", "Василий Кандинский", "Абстрактная геометрическая композиция, масло на холсте, 1923.", .generativeArt, "composition_viii"),
        ("Завтрак гребцов", "Пьер-Огюст Ренуар", "Масло на холсте, 1881. Сцена обеда на открытом воздухе.", .photography, "boating_party"),
        ("Гора Сент-Виктуар", "Поль Сезанн", "Постимпрессионистский пейзаж, масло на холсте, 1902.", .digitalPainting, "mont_sainte_victoire"),
        ("Большая волна", "Кацусика Хокусай", "Гравюра из серии «36 видов Фудзи», 1831.", .pixel, "great_wave"),
        ("Digital Sunrise", "Amara Okafor", "Digital landscape capturing the first light.", .digitalPainting, ""),
        ("Quantum Bloom", "Leo Fischer", "Generative floral patterns from quantum distributions.", .generativeArt, ""),
    ]

    static func makeMockUser() -> User {
        User(
            username: "artcollector",
            displayName: "Alex G.",
            walletAddress: "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
            bio: "Digital art enthusiast & NFT collector",
            balance: 25.0
        )
    }

    static func makeMockArtworks() -> [NFTArtwork] {
        mockArtworkData.enumerated().map { index, data in
            let hasBundled = !data.4.isEmpty
            return NFTArtwork(
                title: data.0,
                artistName: data.1,
                description: data.2,
                imageName: hasBundled ? data.4 : "artwork_\(index)",
                category: data.3,
                createdAt: Date().addingTimeInterval(-Double(index) * 86400),
                tokenId: String(format: "%04d", index + 1),
                contractAddress: "0x\(String(repeating: "a", count: 40))",
                blockchain: index % 2 == 0 ? .ethereum : .polygon,
                imageSource: hasBundled ? .bundled : .procedural
            )
        }
    }

    static func makeMockAuctions() -> [Auction] {
        let artworks = makeMockArtworks()
        let bidders = Array(mockBotBidders.prefix(5))
        return artworks.enumerated().map { index, artwork in
            let startingPrice = Double.random(in: 0.1...5.0)
            let bidCount = Int.random(in: 0...8)
            var currentBid = startingPrice
            var bids: [Bid] = []
            for i in 0..<bidCount {
                currentBid += Double.random(in: 0.05...0.5)
                let bidder = bidders[i % bidders.count]
                bids.append(Bid(
                    id: UUID(),
                    userId: bidder.1,
                    userName: bidder.0,
                    amount: currentBid,
                    timestamp: Date().addingTimeInterval(-Double(bidCount - i) * 3600)
                ))
            }
            let hoursRemaining = index < 2 ? Double.random(in: 0.03...0.08) : Double.random(in: 1...72)
            let buyNow: Double? = index % 3 == 0 ? currentBid * 2.5 : nil
            return Auction(
                id: UUID(),
                artwork: artwork,
                startTime: Date().addingTimeInterval(-Double.random(in: 3600...86400)),
                endTime: Date().addingTimeInterval(hoursRemaining * 3600),
                currentBid: currentBid,
                bids: bids,
                status: index < 10 ? .active : .upcoming,
                startingPrice: startingPrice,
                reservePrice: startingPrice * 2,
                buyNowPrice: buyNow
            )
        }
    }
}
