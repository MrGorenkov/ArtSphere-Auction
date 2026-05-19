import Foundation

struct Auction: Identifiable, Hashable {
    let id: UUID
    var artwork: NFTArtwork
    let startTime: Date
    var endTime: Date
    var currentBid: Double
    var bids: [Bid]
    var status: AuctionStatus
    let startingPrice: Double
    let reservePrice: Double?
    var winnerId: UUID?
    var creatorId: UUID?
    var bidStep: Double?
    var serverBidCount: Int?
    var buyNowPrice: Double?

    var timeRemaining: TimeInterval {
        max(endTime.timeIntervalSince(Date()), 0)
    }

    var isActive: Bool {
        status == .active && timeRemaining > 0
    }

    var hasEnded: Bool {
        timeRemaining <= 0 || status == .ended || status == .sold
    }

    var bidCount: Int {
        bids.count
    }

    var highestBid: Bid? {
        bids.max(by: { $0.amount < $1.amount })
    }

    var formattedCurrentBid: String {
        String(format: "%.2f TON", currentBid)
    }

    /// Smallest bid the server will accept.
    ///
    /// For a lot that has never been bid on, `currentBid` sits at zero, so
    /// `currentBid + step` would let the user submit a tiny amount that the
    /// server then rejects with HTTP 400 ("Bid must be at least starting_price").
    /// Anchor on `startingPrice` until the first real bid arrives.
    var minimumNextBid: Double {
        let base = max(currentBid, startingPrice)
        if let step = bidStep {
            return currentBid > 0 ? currentBid + step : base
        }
        return base + max(base * 0.05, 0.01)
    }

    var isReserveMet: Bool {
        guard let reserve = reservePrice else { return true }
        return currentBid >= reserve
    }

    var hasBuyNow: Bool {
        guard let price = buyNowPrice else { return false }
        return price > currentBid && isActive
    }

    var formattedBuyNowPrice: String? {
        guard let price = buyNowPrice else { return nil }
        return String(format: "%.2f TON", price)
    }

    enum AuctionStatus: String, Codable {
        case upcoming = "Upcoming"
        case active = "Active"
        case ended = "Ended"
        case sold = "Sold"
    }
}

struct Bid: Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    let userName: String
    let amount: Double
    let timestamp: Date

    var formattedAmount: String {
        String(format: "%.2f TON", amount)
    }

    var formattedTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}
