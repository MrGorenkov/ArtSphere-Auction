import Foundation
import Network
import Combine

// MARK: - Queued Bid

struct QueuedBid: Codable, Identifiable {
    let id: UUID
    let auctionId: UUID
    let amount: Double
    let timestamp: Date
}

// MARK: - Sync Response (matches Vapor [BidDTO])

struct SyncBidResponse: Codable {
    let synced: [String]   // IDs of successfully synced bids
    let failed: [String]   // IDs of bids that failed validation
}

// MARK: - Bid Queue Service

final class BidQueueService: ObservableObject {
    static let shared = BidQueueService()

    @Published var pendingBids: [QueuedBid] = []
    @Published var isSyncing = false

    private let network = NetworkService.shared
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.nftarts.bidqueue.monitor")
    private var wasDisconnected = false

    // Exponential backoff
    private var retryAttempt = 0
    private static let maxRetries = 5
    private static let baseDelay: TimeInterval = 1.0

    private static let storageKey = "com.nftarts.queuedBids"

    private init() {
        loadQueue()
        startMonitoring()
    }

    // MARK: - Queue Management

    func queueBid(auctionId: UUID, amount: Double) {
        let bid = QueuedBid(
            id: UUID(),
            auctionId: auctionId,
            amount: amount,
            timestamp: Date()
        )
        pendingBids.append(bid)
        saveQueue()
    }

    var hasPendingBids: Bool { !pendingBids.isEmpty }

    // MARK: - Persistence

    private func loadQueue() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            pendingBids = try decoder.decode([QueuedBid].self, from: data)
        } catch {
            print("[BidQueue] Failed to load queue: \(error)")
            pendingBids = []
        }
    }

    private func saveQueue() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(pendingBids)
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        } catch {
            print("[BidQueue] Failed to save queue: \(error)")
        }
    }

    // MARK: - Network Reachability

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            if path.status == .satisfied {
                if self.wasDisconnected && self.hasPendingBids {
                    DispatchQueue.main.async {
                        self.retryAttempt = 0
                        self.syncQueue()
                    }
                }
                self.wasDisconnected = false
            } else {
                self.wasDisconnected = true
            }
        }
        monitor.start(queue: monitorQueue)
    }

    // MARK: - Sync with Exponential Backoff

    func syncQueue() {
        guard !pendingBids.isEmpty, !isSyncing else { return }
        guard network.authToken != nil else { return }

        isSyncing = true

        let bidsToSync = pendingBids

        struct SyncInput: Codable {
            let id: String
            let auctionId: String
            let amount: Double
            let timestamp: String
        }

        let formatter = ISO8601DateFormatter()
        let inputs = bidsToSync.map { bid in
            SyncInput(
                id: bid.id.uuidString,
                auctionId: bid.auctionId.uuidString,
                amount: bid.amount,
                timestamp: formatter.string(from: bid.timestamp)
            )
        }

        Task {
            do {
                let response: SyncBidResponse = try await network.request(
                    endpoint: "sync/bids",
                    method: .post,
                    body: inputs
                )

                let syncedIds = Set(response.synced)
                let failedIds = Set(response.failed)
                let processedIds = syncedIds.union(failedIds)

                await MainActor.run {
                    self.pendingBids.removeAll { processedIds.contains($0.id.uuidString) }
                    self.saveQueue()
                    self.isSyncing = false
                    self.retryAttempt = 0  // Reset on success
                }

                if !syncedIds.isEmpty {
                    print("[BidQueue] Synced \(syncedIds.count) bids")
                }
                if !failedIds.isEmpty {
                    print("[BidQueue] \(failedIds.count) bids failed validation (removed)")
                }
            } catch {
                print("[BidQueue] Sync failed (attempt \(retryAttempt + 1)): \(error)")
                await MainActor.run { self.isSyncing = false }
                scheduleRetry()
            }
        }
    }

    private func scheduleRetry() {
        retryAttempt += 1
        guard retryAttempt <= Self.maxRetries, hasPendingBids else {
            print("[BidQueue] Max retries (\(Self.maxRetries)) reached, stopping")
            retryAttempt = 0
            return
        }

        let delay = Self.baseDelay * pow(2.0, Double(retryAttempt - 1))
        print("[BidQueue] Retrying in \(delay)s (attempt \(retryAttempt)/\(Self.maxRetries))")

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.syncQueue()
        }
    }

    deinit {
        monitor.cancel()
    }
}
