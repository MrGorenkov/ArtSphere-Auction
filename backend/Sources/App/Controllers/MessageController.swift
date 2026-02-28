import Vapor
import Fluent
import FluentPostgresDriver

struct MessageController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let messages = routes.grouped("messages")
        messages.get(use: getConversations)
        messages.post(use: sendMessage)
        messages.get(":userId", use: getMessages)
        messages.post(":messageId", "read", use: markRead)
    }

    // GET /api/v1/messages — list conversations
    func getConversations(req: Request) async throws -> [ConversationDTO] {
        let myId = try req.auth.require(UUID.self)

        let rows = try await (req.db as! SQLDatabase).raw("""
            SELECT
                CASE WHEN m.sender_id = \(bind: myId) THEN m.receiver_id ELSE m.sender_id END AS other_id,
                u.display_name,
                u.avatar_url,
                m.text AS last_message,
                m.created_at AS last_date,
                COALESCE(unread.cnt, 0) AS unread_count
            FROM messages m
            INNER JOIN LATERAL (
                SELECT id FROM messages m2
                WHERE (m2.sender_id = \(bind: myId) AND m2.receiver_id = m.receiver_id AND m2.sender_id = m.sender_id)
                   OR (m2.receiver_id = \(bind: myId) AND m2.sender_id = m.sender_id AND m2.receiver_id = m.receiver_id)
                   OR (m2.sender_id = \(bind: myId) AND m2.receiver_id = m.sender_id AND m2.sender_id = m.receiver_id)
                   OR (m2.receiver_id = \(bind: myId) AND m2.sender_id = m.receiver_id AND m2.receiver_id = m.sender_id)
                ORDER BY m2.created_at DESC LIMIT 1
            ) latest ON latest.id = m.id
            INNER JOIN users u ON u.id = CASE WHEN m.sender_id = \(bind: myId) THEN m.receiver_id ELSE m.sender_id END
            LEFT JOIN LATERAL (
                SELECT COUNT(*) AS cnt FROM messages
                WHERE sender_id = CASE WHEN m.sender_id = \(bind: myId) THEN m.receiver_id ELSE m.sender_id END
                  AND receiver_id = \(bind: myId)
                  AND is_read = false
            ) unread ON true
            WHERE m.sender_id = \(bind: myId) OR m.receiver_id = \(bind: myId)
            ORDER BY m.created_at DESC
        """).all()

        return try rows.map { row in
            ConversationDTO(
                userId: try row.decode(column: "other_id", as: UUID.self).uuidString,
                userName: try row.decode(column: "display_name", as: String.self),
                avatarUrl: try? row.decode(column: "avatar_url", as: String.self),
                lastMessage: try row.decode(column: "last_message", as: String.self),
                lastMessageDate: (try? row.decode(column: "last_date", as: Date.self))?.iso8601String ?? "",
                unreadCount: try row.decode(column: "unread_count", as: Int.self)
            )
        }
    }

    // POST /api/v1/messages — send message (optionally with artwork share)
    func sendMessage(req: Request) async throws -> MessageDTO {
        let myId = try req.auth.require(UUID.self)
        let body = try req.content.decode(SendMessageRequest.self)

        guard let receiverId = UUID(uuidString: body.receiverId) else {
            throw Abort(.badRequest, reason: "Invalid receiver ID")
        }
        guard myId != receiverId else {
            throw Abort(.badRequest, reason: "Cannot send message to yourself")
        }

        let artworkId = body.artworkId.flatMap { UUID(uuidString: $0) }

        guard let sender = try await UserModel.find(myId, on: req.db) else {
            throw Abort(.notFound, reason: "Sender not found")
        }
        guard let receiver = try await UserModel.find(receiverId, on: req.db) else {
            throw Abort(.notFound, reason: "Receiver not found")
        }

        var artwork: ArtworkModel?
        if let artworkId {
            artwork = try await ArtworkModel.find(artworkId, on: req.db)
        }

        let message = MessageModel(
            senderId: myId,
            receiverId: receiverId,
            artworkId: artworkId,
            text: body.text
        )
        try await message.save(on: req.db)

        // Create notification for receiver
        let notifType = artworkId != nil ? "artwork_shared" : "message"
        let notifTitle = artworkId != nil
            ? "\(sender.displayName) shared an artwork"
            : "\(sender.displayName) sent you a message"
        let notifMessage = artworkId != nil
            ? (artwork?.title ?? "Artwork")
            : String(body.text.prefix(100))

        try await (req.db as! SQLDatabase).raw("""
            INSERT INTO notifications (user_id, type, title, message, related_artwork_id)
            VALUES (\(bind: receiverId), \(bind: notifType), \(bind: notifTitle), \(bind: notifMessage), \(bind: artworkId))
        """).run()

        // Send real-time notification via WebSocket
        let wsNotif = ["type": notifType, "senderId": myId.uuidString, "senderName": sender.displayName, "message": notifMessage]
        if let data = try? JSONSerialization.data(withJSONObject: wsNotif),
           let json = String(data: data, encoding: .utf8) {
            await WebSocketManager.shared.sendToUser(receiverId, message: json)
        }

        return MessageDTO(
            id: message.id?.uuidString ?? "",
            senderId: myId.uuidString,
            senderName: sender.displayName,
            senderAvatarUrl: sender.avatarUrl,
            receiverId: receiverId.uuidString,
            receiverName: receiver.displayName,
            artworkId: artworkId?.uuidString,
            artworkTitle: artwork?.title,
            artworkImageUrl: artwork?.imageUrl,
            text: body.text,
            isRead: false,
            createdAt: message.createdAt?.iso8601String ?? ""
        )
    }

    // GET /api/v1/messages/:userId — get messages with a specific user
    func getMessages(req: Request) async throws -> [MessageDTO] {
        let myId = try req.auth.require(UUID.self)
        guard let otherId = req.parameters.get("userId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid user ID")
        }

        // Mark received messages as read
        try await (req.db as! SQLDatabase).raw("""
            UPDATE messages SET is_read = true
            WHERE sender_id = \(bind: otherId) AND receiver_id = \(bind: myId) AND is_read = false
        """).run()

        let rows = try await (req.db as! SQLDatabase).raw("""
            SELECT m.id, m.sender_id, m.receiver_id, m.artwork_id, m.text, m.is_read, m.created_at,
                   su.display_name AS sender_name, su.avatar_url AS sender_avatar,
                   ru.display_name AS receiver_name,
                   a.title AS artwork_title, a.image_url AS artwork_image
            FROM messages m
            INNER JOIN users su ON su.id = m.sender_id
            INNER JOIN users ru ON ru.id = m.receiver_id
            LEFT JOIN artworks a ON a.id = m.artwork_id
            WHERE (m.sender_id = \(bind: myId) AND m.receiver_id = \(bind: otherId))
               OR (m.sender_id = \(bind: otherId) AND m.receiver_id = \(bind: myId))
            ORDER BY m.created_at ASC
            LIMIT 200
        """).all()

        return try rows.map { row in
            MessageDTO(
                id: try row.decode(column: "id", as: UUID.self).uuidString,
                senderId: try row.decode(column: "sender_id", as: UUID.self).uuidString,
                senderName: try row.decode(column: "sender_name", as: String.self),
                senderAvatarUrl: try? row.decode(column: "sender_avatar", as: String.self),
                receiverId: try row.decode(column: "receiver_id", as: UUID.self).uuidString,
                receiverName: try row.decode(column: "receiver_name", as: String.self),
                artworkId: (try? row.decode(column: "artwork_id", as: UUID.self))?.uuidString,
                artworkTitle: try? row.decode(column: "artwork_title", as: String.self),
                artworkImageUrl: try? row.decode(column: "artwork_image", as: String.self),
                text: try row.decode(column: "text", as: String.self),
                isRead: try row.decode(column: "is_read", as: Bool.self),
                createdAt: (try? row.decode(column: "created_at", as: Date.self))?.iso8601String ?? ""
            )
        }
    }

    // POST /api/v1/messages/:messageId/read — mark as read
    func markRead(req: Request) async throws -> HTTPStatus {
        let myId = try req.auth.require(UUID.self)
        guard let messageId = req.parameters.get("messageId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid message ID")
        }

        guard let message = try await MessageModel.find(messageId, on: req.db) else {
            throw Abort(.notFound, reason: "Message not found")
        }
        guard message.receiverId == myId else {
            throw Abort(.forbidden, reason: "Cannot mark another user's message as read")
        }

        message.isRead = true
        try await message.save(on: req.db)
        return .noContent
    }
}
