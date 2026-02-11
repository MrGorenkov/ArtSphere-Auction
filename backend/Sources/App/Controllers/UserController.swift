import Vapor
import Fluent
import FluentPostgresDriver

struct UserController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let users = routes.grouped("users")
        users.get("me", use: profile)
        users.get("me", "stats", use: stats)
        users.get("me", "notifications", use: notifications)
        users.put("me", use: updateProfile)
        users.on(.POST, "me", "avatar", body: .collect(maxSize: "5mb"), use: uploadAvatar)
        users.post("me", "device-token", use: registerDeviceToken)
    }

    // GET /api/v1/users/me
    func profile(req: Request) async throws -> UserDTO {
        let userId = try req.auth.require(UUID.self)

        guard let user = try await UserModel.find(userId, on: req.db) else {
            throw Abort(.notFound, reason: "User not found")
        }

        return user.toDTO()
    }

    // PUT /api/v1/users/me
    func updateProfile(req: Request) async throws -> UserDTO {
        let userId = try req.auth.require(UUID.self)

        guard let user = try await UserModel.find(userId, on: req.db) else {
            throw Abort(.notFound, reason: "User not found")
        }

        let body = try req.content.decode(UpdateProfileRequest.self)
        if let displayName = body.displayName { user.displayName = displayName }
        if let bio = body.bio { user.bio = bio }
        if let email = body.email { user.email = email }
        if let cardNumber = body.cardNumber { user.cardNumber = cardNumber }

        try await user.save(on: req.db)
        return user.toDTO()
    }

    // POST /api/v1/users/me/avatar
    func uploadAvatar(req: Request) async throws -> UserDTO {
        let userId = try req.auth.require(UUID.self)

        guard let user = try await UserModel.find(userId, on: req.db) else {
            throw Abort(.notFound, reason: "User not found")
        }

        let file = try req.content.decode(FileUpload.self)
        let ext = file.file.filename.split(separator: ".").last.map(String.init) ?? "png"
        let key = "\(userId.uuidString).\(ext)"

        let url = try await req.minio.upload(
            data: file.file.data,
            bucket: MinIOService.avatarsBucket,
            key: key,
            contentType: file.file.contentType?.description ?? "image/png",
            on: req.client
        )

        user.avatarUrl = url
        try await user.save(on: req.db)
        return user.toDTO()
    }

    // GET /api/v1/users/me/stats
    func stats(req: Request) async throws -> UserStatsDTO {
        let userId = try req.auth.require(UUID.self)

        let collectionsCount = try await CollectionModel.query(on: req.db)
            .filter(\.$user.$id == userId)
            .count()

        let auctionsWon = try await AuctionModel.query(on: req.db)
            .filter(\.$winnerId == userId)
            .filter(\.$status == "sold")
            .count()

        // Raw SQL for tables without Fluent models
        let db = req.db as! SQLDatabase
        let ownedRow = try await db.raw("SELECT COUNT(*) AS cnt FROM owned_artworks WHERE user_id = \(bind: userId)")
            .first()
        let ownedCount = try ownedRow?.decode(column: "cnt", as: Int.self) ?? 0

        let favRow = try await db.raw("SELECT COUNT(*) AS cnt FROM favorites WHERE user_id = \(bind: userId)")
            .first()
        let favoritesCount = try favRow?.decode(column: "cnt", as: Int.self) ?? 0

        return UserStatsDTO(
            ownedNFTs: ownedCount,
            favorites: favoritesCount,
            collections: collectionsCount,
            auctionsWon: auctionsWon
        )
    }

    // GET /api/v1/users/me/notifications
    func notifications(req: Request) async throws -> [NotificationDTO] {
        let userId = try req.auth.require(UUID.self)

        let db = req.db as! SQLDatabase
        let rows = try await db.raw("""
            SELECT id, type, title, message, is_read, created_at
            FROM notifications
            WHERE user_id = \(bind: userId)
            ORDER BY created_at DESC
            LIMIT 50
            """)
            .all()

        return rows.compactMap { row -> NotificationDTO? in
            guard let id = try? row.decode(column: "id", as: UUID.self),
                  let type = try? row.decode(column: "type", as: String.self),
                  let title = try? row.decode(column: "title", as: String.self),
                  let message = try? row.decode(column: "message", as: String.self),
                  let isRead = try? row.decode(column: "is_read", as: Bool.self),
                  let createdAt = try? row.decode(column: "created_at", as: Date.self)
            else { return nil }

            return NotificationDTO(
                id: id.uuidString,
                type: type,
                title: title,
                message: message,
                isRead: isRead,
                createdAt: createdAt.iso8601String
            )
        }
    }
    // POST /api/v1/users/me/device-token
    func registerDeviceToken(req: Request) async throws -> HTTPStatus {
        let userId = try req.auth.require(UUID.self)
        let body = try req.content.decode(DeviceTokenRequest.self)

        let db = req.db as! SQLDatabase
        // Upsert device token (replace if same user+platform exists)
        try await db.raw("""
            INSERT INTO device_tokens (id, user_id, token, platform, created_at)
            VALUES (\(bind: UUID()), \(bind: userId), \(bind: body.token), \(bind: body.platform), NOW())
            ON CONFLICT (user_id, platform)
            DO UPDATE SET token = \(bind: body.token), created_at = NOW()
            """)
            .run()

        return .ok
    }
}

struct UserStatsDTO: Content {
    let ownedNFTs: Int
    let favorites: Int
    let collections: Int
    let auctionsWon: Int
}

struct NotificationDTO: Content {
    let id: String
    let type: String
    let title: String
    let message: String
    let isRead: Bool
    let createdAt: String
}

struct UpdateProfileRequest: Content {
    let displayName: String?
    let bio: String?
    let email: String?
    let cardNumber: String?
}

struct DeviceTokenRequest: Content {
    let token: String
    let platform: String
}
