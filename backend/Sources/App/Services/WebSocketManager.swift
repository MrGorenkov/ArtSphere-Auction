import Vapor
import Foundation

/// Менеджер WebSocket-подключений для real-time обновлений аукционов
actor WebSocketManager {
    static let shared = WebSocketManager()

    // auctionId -> [WebSocket]
    private var auctionSubscribers: [UUID: [WebSocket]] = [:]
    // userId -> [WebSocket]
    private var userConnections: [UUID: [WebSocket]] = [:]
    // Global feed subscribers (receive ALL auction bid/status updates)
    private var feedSubscribers: [WebSocket] = []

    private init() {}

    // MARK: - Подписка на аукцион

    func subscribe(to auctionId: UUID, socket: WebSocket) {
        var subs = auctionSubscribers[auctionId] ?? []
        subs.append(socket)
        auctionSubscribers[auctionId] = subs
    }

    func unsubscribe(from auctionId: UUID, socket: WebSocket) {
        auctionSubscribers[auctionId]?.removeAll { $0 === socket }
        if auctionSubscribers[auctionId]?.isEmpty == true {
            auctionSubscribers.removeValue(forKey: auctionId)
        }
    }

    // MARK: - Global Feed

    func subscribeFeed(socket: WebSocket) {
        feedSubscribers.append(socket)
    }

    func unsubscribeFeed(socket: WebSocket) {
        feedSubscribers.removeAll { $0 === socket }
    }

    // MARK: - Подключение пользователя (уведомления)

    func connectUser(_ userId: UUID, socket: WebSocket) {
        var conns = userConnections[userId] ?? []
        conns.append(socket)
        userConnections[userId] = conns
    }

    func disconnectUser(_ userId: UUID, socket: WebSocket) {
        userConnections[userId]?.removeAll { $0 === socket }
        if userConnections[userId]?.isEmpty == true {
            userConnections.removeValue(forKey: userId)
        }
    }

    // MARK: - Отправка сообщений

    /// Отправить обновление ставки всем подписчикам аукциона + глобальной ленте
    func broadcastBid(_ message: WSBidMessage, auctionId: UUID) async {
        let encoder = JSONEncoder()

        guard let data = try? encoder.encode(message),
              let json = String(data: data, encoding: .utf8) else { return }

        // Send to per-auction subscribers
        if let subscribers = auctionSubscribers[auctionId] {
            for socket in subscribers where !socket.isClosed {
                try? await socket.send(json)
            }
            auctionSubscribers[auctionId]?.removeAll { $0.isClosed }
        }

        // Send to global feed subscribers
        for socket in feedSubscribers where !socket.isClosed {
            try? await socket.send(json)
        }
        feedSubscribers.removeAll { $0.isClosed }
    }

    /// Отправить обновление статуса аукциона
    func broadcastAuctionUpdate(_ message: WSAuctionUpdate, auctionId: UUID) async {
        let encoder = JSONEncoder()

        guard let data = try? encoder.encode(message),
              let json = String(data: data, encoding: .utf8) else { return }

        if let subscribers = auctionSubscribers[auctionId] {
            for socket in subscribers where !socket.isClosed {
                try? await socket.send(json)
            }
        }

        // Also broadcast to global feed
        for socket in feedSubscribers where !socket.isClosed {
            try? await socket.send(json)
        }
        feedSubscribers.removeAll { $0.isClosed }
    }

    /// Отправить уведомление конкретному пользователю
    func sendToUser(_ userId: UUID, message: String) async {
        guard let connections = userConnections[userId] else { return }

        for socket in connections where !socket.isClosed {
            try? await socket.send(message)
        }

        userConnections[userId]?.removeAll { $0.isClosed }
    }

    /// Очистить все закрытые соединения
    func cleanup() {
        for (auctionId, sockets) in auctionSubscribers {
            auctionSubscribers[auctionId] = sockets.filter { !$0.isClosed }
            if auctionSubscribers[auctionId]?.isEmpty == true {
                auctionSubscribers.removeValue(forKey: auctionId)
            }
        }

        for (userId, sockets) in userConnections {
            userConnections[userId] = sockets.filter { !$0.isClosed }
            if userConnections[userId]?.isEmpty == true {
                userConnections.removeValue(forKey: userId)
            }
        }

        feedSubscribers.removeAll { $0.isClosed }
    }
}
