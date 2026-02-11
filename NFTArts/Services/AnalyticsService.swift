import Foundation

/// Analytics events tracked in the app.
enum AnalyticsEvent: String {
    // Auth
    case login = "user_login"
    case register = "user_register"
    case logout = "user_logout"

    // Bidding
    case bidPlaced = "bid_placed"
    case bidFailed = "bid_failed"
    case auctionWon = "auction_won"
    case outbid = "user_outbid"

    // NFT Creation
    case nftCreated = "nft_created"
    case imageUploaded = "image_uploaded"

    // 3D / AR
    case view3D = "view_3d"
    case viewAR = "view_ar"
    case arPlaced = "ar_artwork_placed"

    // Navigation
    case screenView = "screen_view"
    case feedRefresh = "feed_refresh"
    case searchUsed = "search_used"

    // Collections
    case collectionCreated = "collection_created"
    case collectionDeleted = "collection_deleted"
    case addedToCollection = "added_to_collection"

    // Profile
    case profileEdited = "profile_edited"
    case avatarUploaded = "avatar_uploaded"
}

/// Centralized analytics service.
/// Logs events locally and can be wired to Firebase Analytics when configured.
///
/// To enable Firebase Analytics:
/// 1. Add `firebase-ios-sdk` SPM package to project.yml
/// 2. Add `GoogleService-Info.plist` from Firebase Console
/// 3. Call `FirebaseApp.configure()` in NFTArtsApp.init()
/// 4. Uncomment Firebase import and `Analytics.logEvent` calls below
final class AnalyticsService {
    static let shared = AnalyticsService()

    private var isEnabled = true
    private var userId: String?
    private var sessionEvents: [(event: String, params: [String: Any], timestamp: Date)] = []

    private init() {}

    // MARK: - Configuration

    func setUserId(_ id: String) {
        self.userId = id
        // Firebase: Analytics.setUserID(id)
        log("Set user ID: \(id)")
    }

    func setUserProperty(_ value: String, forName name: String) {
        // Firebase: Analytics.setUserProperty(value, forName: name)
        log("User property \(name) = \(value)")
    }

    // MARK: - Event Tracking

    func track(_ event: AnalyticsEvent, parameters: [String: Any]? = nil) {
        guard isEnabled else { return }

        var params = parameters ?? [:]
        if let userId { params["user_id"] = userId }
        params["timestamp"] = ISO8601DateFormatter().string(from: Date())

        // Firebase: Analytics.logEvent(event.rawValue, parameters: params)

        // Local logging
        sessionEvents.append((event: event.rawValue, params: params, timestamp: Date()))
        log("Event: \(event.rawValue) | \(params)")

        // Keep last 500 events in memory
        if sessionEvents.count > 500 {
            sessionEvents = Array(sessionEvents.suffix(500))
        }
    }

    // MARK: - Screen Tracking

    func trackScreen(_ screenName: String, screenClass: String? = nil) {
        track(.screenView, parameters: [
            "screen_name": screenName,
            "screen_class": screenClass ?? screenName
        ])
        // Firebase: Analytics.logEvent(AnalyticsEventScreenView, parameters: [...])
    }

    // MARK: - Convenience Methods

    func trackBid(auctionId: String, amount: Double, artworkTitle: String) {
        track(.bidPlaced, parameters: [
            "auction_id": auctionId,
            "bid_amount": amount,
            "artwork_title": artworkTitle
        ])
    }

    func trackNFTCreated(title: String, category: String, startingPrice: Double) {
        track(.nftCreated, parameters: [
            "title": title,
            "category": category,
            "starting_price": startingPrice
        ])
    }

    func trackAR(artworkId: String, artworkTitle: String) {
        track(.viewAR, parameters: [
            "artwork_id": artworkId,
            "artwork_title": artworkTitle
        ])
    }

    func track3D(artworkId: String, artworkTitle: String) {
        track(.view3D, parameters: [
            "artwork_id": artworkId,
            "artwork_title": artworkTitle
        ])
    }

    // MARK: - Session Summary

    /// Returns a summary of tracked events this session (useful for debugging).
    var sessionSummary: [String: Int] {
        var counts: [String: Int] = [:]
        for event in sessionEvents {
            counts[event.event, default: 0] += 1
        }
        return counts
    }

    // MARK: - Private

    private func log(_ message: String) {
        #if DEBUG
        print("[Analytics] \(message)")
        #endif
    }
}
