import Foundation
import Combine

// MARK: - WebSocketService

/// Observable singleton that manages WebSocket connections for real-time auction
/// updates and personal user notifications.
///
/// Endpoints:
/// - `ws://<host>/ws/auctions/feed`       -- global feed of all bid/status updates
/// - `ws://<host>/ws/user/:userId`        -- personal notifications for the current user
final class WebSocketService: ObservableObject {
    static let shared = WebSocketService()

    // MARK: - Published State

    @Published var latestBidUpdate: WSBidUpdate?
    @Published var latestAuctionUpdate: WSAuctionStatusUpdate?
    @Published var latestUserNotification: WSUserNotification?
    @Published var isFeedConnected: Bool = false
    @Published var isUserConnected: Bool = false

    // MARK: - WebSocket Tasks

    private var feedTask: URLSessionWebSocketTask?
    private var userTask: URLSessionWebSocketTask?
    private let session: URLSession

    // MARK: - Reconnect State

    private var feedReconnectAttempts: Int = 0
    private var currentUserId: String?
    private var userReconnectAttempts: Int = 0
    private static let maxReconnectAttempts = 5
    private static let reconnectBaseDelay: TimeInterval = 1.0

    // MARK: - Base URL

    private var wsBaseURL: String {
        #if DEBUG
        return "ws://192.168.1.54:8080"
        #else
        return "wss://api.nftarts.com"
        #endif
    }

    // MARK: - Init

    private init() {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    // MARK: - Global Auction Feed

    /// Opens a WebSocket connection to receive ALL auction bid and status updates.
    func subscribeToAuctionFeed() {
        unsubscribeFromFeed()

        guard let url = URL(string: "\(wsBaseURL)/ws/auctions/feed") else { return }

        feedReconnectAttempts = 0

        let task = session.webSocketTask(with: url)
        feedTask = task
        task.resume()

        DispatchQueue.main.async { self.isFeedConnected = true }
        receiveFeedMessages()
        sendFeedPing()
    }

    /// Closes the auction feed WebSocket connection.
    func unsubscribeFromFeed() {
        feedTask?.cancel(with: .goingAway, reason: nil)
        feedTask = nil
        feedReconnectAttempts = 0
        DispatchQueue.main.async { self.isFeedConnected = false }
    }

    // MARK: - User Subscription

    /// Opens a WebSocket connection for personal notifications for the given user.
    func subscribeToUser(_ userId: String) {
        unsubscribeFromUser()

        guard let url = URL(string: "\(wsBaseURL)/ws/user/\(userId)") else { return }

        currentUserId = userId
        userReconnectAttempts = 0

        let task = session.webSocketTask(with: url)
        userTask = task
        task.resume()

        DispatchQueue.main.async { self.isUserConnected = true }
        receiveUserMessages()
        sendUserPing()
    }

    /// Closes the user notifications WebSocket connection.
    func unsubscribeFromUser() {
        userTask?.cancel(with: .goingAway, reason: nil)
        userTask = nil
        currentUserId = nil
        userReconnectAttempts = 0
        DispatchQueue.main.async { self.isUserConnected = false }
    }

    // MARK: - Disconnect All

    func disconnectAll() {
        unsubscribeFromFeed()
        unsubscribeFromUser()
    }

    // MARK: - Feed Message Handling

    private func receiveFeedMessages() {
        feedTask?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleFeedMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleFeedMessage(text)
                    }
                @unknown default:
                    break
                }
                self.receiveFeedMessages()

            case .failure:
                DispatchQueue.main.async { self.isFeedConnected = false }
                self.attemptFeedReconnect()
            }
        }
    }

    private func handleFeedMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        let decoder = JSONDecoder()

        if let bidUpdate = try? decoder.decode(WSBidUpdate.self, from: data),
           bidUpdate.type == "new_bid" {
            DispatchQueue.main.async {
                self.latestBidUpdate = bidUpdate
            }
            return
        }

        if let statusUpdate = try? decoder.decode(WSAuctionStatusUpdate.self, from: data),
           statusUpdate.type == "auction_status" || statusUpdate.type == "auction_update" {
            DispatchQueue.main.async {
                self.latestAuctionUpdate = statusUpdate
            }
            return
        }
    }

    // MARK: - User Message Handling

    private func receiveUserMessages() {
        userTask?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleUserMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleUserMessage(text)
                    }
                @unknown default:
                    break
                }
                self.receiveUserMessages()

            case .failure:
                DispatchQueue.main.async { self.isUserConnected = false }
                self.attemptUserReconnect()
            }
        }
    }

    private func handleUserMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        let decoder = JSONDecoder()

        if let notification = try? decoder.decode(WSUserNotification.self, from: data) {
            DispatchQueue.main.async {
                self.latestUserNotification = notification
            }
        }
    }

    // MARK: - Keep-Alive Pings

    private func sendFeedPing() {
        guard feedTask != nil else { return }
        feedTask?.sendPing { [weak self] error in
            guard let self, error == nil else { return }
            DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
                self.sendFeedPing()
            }
        }
    }

    private func sendUserPing() {
        guard userTask != nil else { return }
        userTask?.sendPing { [weak self] error in
            guard let self, error == nil else { return }
            DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
                self.sendUserPing()
            }
        }
    }

    // MARK: - Auto-Reconnect

    private func attemptFeedReconnect() {
        guard feedReconnectAttempts < Self.maxReconnectAttempts else { return }

        feedReconnectAttempts += 1
        let delay = Self.reconnectBaseDelay * pow(2.0, Double(feedReconnectAttempts - 1))

        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            guard let url = URL(string: "\(self.wsBaseURL)/ws/auctions/feed") else { return }

            let task = self.session.webSocketTask(with: url)
            self.feedTask = task
            task.resume()

            DispatchQueue.main.async { self.isFeedConnected = true }
            self.receiveFeedMessages()
            self.sendFeedPing()
        }
    }

    private func attemptUserReconnect() {
        guard userReconnectAttempts < Self.maxReconnectAttempts,
              let userId = currentUserId else { return }

        userReconnectAttempts += 1
        let delay = Self.reconnectBaseDelay * pow(2.0, Double(userReconnectAttempts - 1))

        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            guard let url = URL(string: "\(self.wsBaseURL)/ws/user/\(userId)") else { return }

            let task = self.session.webSocketTask(with: url)
            self.userTask = task
            task.resume()

            DispatchQueue.main.async { self.isUserConnected = true }
            self.receiveUserMessages()
            self.sendUserPing()
        }
    }
}

// MARK: - WebSocket Message Types

extension WebSocketService {

    struct WSBidUpdate: Codable, Equatable {
        let type: String          // "new_bid"
        let auctionId: String
        let bid: WSBidInfo
        let currentBid: Double
        let bidCount: Int
    }

    struct WSBidInfo: Codable, Equatable {
        let id: String
        let auctionId: String
        let userId: String
        let userName: String
        let amount: Double
        let timestamp: String
    }

    struct WSAuctionStatusUpdate: Codable, Equatable {
        let type: String          // "auction_status" or "auction_update"
        let auctionId: String
        let status: String
        let winnerId: String?
    }

    struct WSUserNotification: Codable, Equatable {
        let type: String          // e.g. "outbid", "auction_won", "notification"
        let title: String?
        let message: String?
        let auctionId: String?
        let artworkId: String?
    }
}
