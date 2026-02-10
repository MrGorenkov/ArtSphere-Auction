import Vapor
import Foundation

/// Менеджер WebSocket-подключений для real-time обновлений аукционов
actor WebSocketManager {
    static let shared = WebSocketManager()

    // auctionId -> [WebSocket]
    private var auctionSubscribers: [UUID: [WebSocket]] = [:]
    // userId -> [WebSocket]
    private var userConnections: [UUID: [WebSocket]] = [:]

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

    /// Отправить обновление ставки всем подписчикам аукциона
    func broadcastBid(_ message: WSBidMessage, auctionId: UUID) async {
        guard let subscribers = auctionSubscribers[auctionId] else { return }
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        guard let data = try? encoder.encode(message),
              let json = String(data: data, encoding: .utf8) else { return }

        for socket in subscribers {
            if !socket.isClosed {
                try? await socket.send(json)
            }
        }

        // Очистить закрытые соединения
        auctionSubscribers[auctionId]?.removeAll { $0.isClosed }
    }

    /// Отправить обновление статуса аукциона
    func broadcastAuctionUpdate(_ message: WSAuctionUpdate, auctionId: UUID) async {
        guard let subscribers = auctionSubscribers[auctionId] else { return }
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        guard let data = try? encoder.encode(message),
              let json = String(data: data, encoding: .utf8) else { return }

        for socket in subscribers {
            if !socket.isClosed {
                try? await socket.send(json)
            }
        }
    }

    /// Отправить уведомление конкретному пользователю
    func sendToUser(_ userId: UUID, message: String) async {
        guard let connections = userConnections[userId] else { return }

        for socket in connections {
            if !socket.isClosed {
                try? await socket.send(message)
            }
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
    }
}
