import Foundation

/// Singleton service for collecting performance and interaction metrics.
/// Used for the scientific paper — captures timing, counts, and analysis data.
final class MetricsService {
    static let shared = MetricsService()

    private var entries: [MetricEntry] = []
    private let queue = DispatchQueue(label: "com.nftarts.metrics", attributes: .concurrent)
    private let sessionStart = Date()

    private init() {}

    // MARK: - Data Model

    struct MetricEntry: Codable {
        let category: String
        let name: String
        let value: Double
        let unit: String
        let timestamp: Date
        let metadata: [String: String]?
    }

    // MARK: - Recording

    /// Record a single metric value.
    func record(category: String, name: String, value: Double, unit: String = "", metadata: [String: String]? = nil) {
        let entry = MetricEntry(
            category: category,
            name: name,
            value: value,
            unit: unit,
            timestamp: Date(),
            metadata: metadata
        )
        queue.async(flags: .barrier) {
            self.entries.append(entry)
        }
        #if DEBUG
        let meta = metadata.map { " \($0)" } ?? ""
        print("[Metrics] \(category)/\(name): \(String(format: "%.2f", value)) \(unit)\(meta)")
        #endif
    }

    /// Measure a synchronous block and record duration in ms.
    @discardableResult
    func measure<T>(category: String, name: String, metadata: [String: String]? = nil, block: () -> T) -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = block()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        record(category: category, name: name, value: elapsed, unit: "ms", metadata: metadata)
        return result
    }

    /// Measure an async block and record duration in ms.
    @discardableResult
    func measureAsync<T>(category: String, name: String, metadata: [String: String]? = nil, block: () async throws -> T) async rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = try await block()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        record(category: category, name: name, value: elapsed, unit: "ms", metadata: metadata)
        return result
    }

    // MARK: - Feature Usage Tracking

    func trackFeatureUsage(_ feature: String) {
        record(category: "interaction", name: "feature_usage", value: 1, unit: "count", metadata: ["feature": feature])
    }

    func trackBidPlaced(amount: Double, auctionId: String) {
        record(category: "interaction", name: "bid_placed", value: amount, unit: "ETH", metadata: ["auction_id": auctionId])
    }

    func trackARPlacement(surface: String) {
        record(category: "ar_performance", name: "artwork_placed", value: 1, unit: "count", metadata: ["surface": surface])
    }

    // MARK: - Export

    /// Returns all collected metrics as JSON Data.
    func exportJSON() -> Data? {
        var snapshot: [MetricEntry] = []
        queue.sync { snapshot = self.entries }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(snapshot)
    }

    /// Returns a human-readable summary of collected metrics.
    func summary() -> String {
        var snapshot: [MetricEntry] = []
        queue.sync { snapshot = self.entries }

        let sessionDuration = Date().timeIntervalSince(sessionStart)

        // Group by category
        var grouped: [String: [MetricEntry]] = [:]
        for entry in snapshot {
            grouped[entry.category, default: []].append(entry)
        }

        var lines: [String] = []
        lines.append("=== NFT Arts Metrics Summary ===")
        lines.append("Session duration: \(String(format: "%.0f", sessionDuration))s")
        lines.append("Total metrics: \(snapshot.count)")
        lines.append("")

        for (category, entries) in grouped.sorted(by: { $0.key < $1.key }) {
            lines.append("[\(category)]")

            // Group by name within category
            var byName: [String: [MetricEntry]] = [:]
            for e in entries { byName[e.name, default: []].append(e) }

            for (name, nameEntries) in byName.sorted(by: { $0.key < $1.key }) {
                let values = nameEntries.map { $0.value }
                let count = values.count
                let avg = values.reduce(0, +) / Double(count)
                let unit = nameEntries.first?.unit ?? ""

                if count == 1 {
                    lines.append("  \(name): \(String(format: "%.2f", avg)) \(unit)")
                } else {
                    let minVal = values.min() ?? 0
                    let maxVal = values.max() ?? 0
                    lines.append("  \(name): avg=\(String(format: "%.2f", avg)) min=\(String(format: "%.2f", minVal)) max=\(String(format: "%.2f", maxVal)) \(unit) (n=\(count))")
                }
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// Clear all metrics.
    func reset() {
        queue.async(flags: .barrier) {
            self.entries.removeAll()
        }
    }
}
