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
        String(format: "%.2f ETH", currentBid)
    }

    var minimumNextBid: Double {
        currentBid + max(currentBid * 0.05, 0.01)
    }

    var isReserveMet: Bool {
        guard let reserve = reservePrice else { return true }
        return currentBid >= reserve
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
        String(format: "%.2f ETH", amount)
    }

    var formattedTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}
