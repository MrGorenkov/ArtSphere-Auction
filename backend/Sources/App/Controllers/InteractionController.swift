import Vapor
import Fluent
import FluentPostgresDriver

struct InteractionController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        // Comments
        let comments = routes.grouped("artworks")
        comments.get(":artworkId", "comments", use: getComments)
        comments.post(":artworkId", "comments", use: addComment)
        comments.delete("comments", ":commentId", use: deleteComment)

        // Likes
        let likes = routes.grouped("artworks")
        likes.get(":artworkId", "likes", use: getLikeStatus)
        likes.post(":artworkId", "like", use: toggleLike)

        // Follows
        let follows = routes.grouped("users")
        follows.get(":userId", "profile", use: getUserProfile)
        follows.post(":userId", "follow", use: toggleFollow)
        follows.get("me", "following", use: getFollowing)
        follows.get("me", "followers", use: getFollowers)
    }

    // MARK: - Comments

    // GET /api/v1/artworks/:artworkId/comments
    func getComments(req: Request) async throws -> [CommentDTO] {
        guard let artworkId = req.parameters.get("artworkId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid artwork ID")
        }

        let comments = try await CommentModel.query(on: req.db)
            .filter(\.$artwork.$id == artworkId)
            .sort(\.$createdAt, .descending)
            .limit(100)
            .all()

        // Batch load user info
        let userIds = comments.map { $0.$user.id }
        let users = try await UserModel.query(on: req.db)
            .filter(\.$id ~~ userIds)
            .all()
        let userMap = Dictionary(uniqueKeysWithValues: users.map { ($0.id!, $0) })

        return comments.map { comment in
            let user = userMap[comment.$user.id]
            return CommentDTO(
                id: comment.id?.uuidString ?? "",
                artworkId: comment.$artwork.id.uuidString,
                userId: comment.$user.id.uuidString,
                userName: user?.displayName ?? "Unknown",
                avatarUrl: user?.avatarUrl,
                text: comment.text,
                createdAt: comment.createdAt?.iso8601String ?? ""
            )
        }
    }

    // POST /api/v1/artworks/:artworkId/comments
    func addComment(req: Request) async throws -> CommentDTO {
        let userId = try req.auth.require(UUID.self)
        guard let artworkId = req.parameters.get("artworkId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid artwork ID")
        }

        let body = try req.content.decode(CreateCommentRequest.self)
        guard !body.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Abort(.badRequest, reason: "Comment text cannot be empty")
        }

        guard let user = try await UserModel.find(userId, on: req.db) else {
            throw Abort(.notFound, reason: "User not found")
        }

        let comment = CommentModel(artworkId: artworkId, userId: userId, text: body.text)
        try await comment.save(on: req.db)

        return CommentDTO(
            id: comment.id?.uuidString ?? "",
            artworkId: artworkId.uuidString,
            userId: userId.uuidString,
            userName: user.displayName,
            avatarUrl: user.avatarUrl,
            text: comment.text,
            createdAt: comment.createdAt?.iso8601String ?? ""
        )
    }

    // DELETE /api/v1/artworks/comments/:commentId
    func deleteComment(req: Request) async throws -> HTTPStatus {
        let userId = try req.auth.require(UUID.self)
        guard let commentId = req.parameters.get("commentId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid comment ID")
        }

        guard let comment = try await CommentModel.find(commentId, on: req.db) else {
            throw Abort(.notFound, reason: "Comment not found")
        }

        guard comment.$user.id == userId else {
            throw Abort(.forbidden, reason: "Cannot delete another user's comment")
        }

        try await comment.delete(on: req.db)
        return .noContent
    }

    // MARK: - Likes

    // GET /api/v1/artworks/:artworkId/likes
    func getLikeStatus(req: Request) async throws -> LikeStatusDTO {
        let userId = try req.auth.require(UUID.self)
        guard let artworkId = req.parameters.get("artworkId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid artwork ID")
        }

        let countRow = try await (req.db as! SQLDatabase).raw("SELECT COUNT(*) AS cnt FROM likes WHERE artwork_id = \(bind: artworkId)")
            .first()
        let likeCount = try countRow?.decode(column: "cnt", as: Int.self) ?? 0

        let myLike = try await (req.db as! SQLDatabase).raw(
            "SELECT 1 FROM likes WHERE user_id = \(bind: userId) AND artwork_id = \(bind: artworkId)"
        ).first()

        return LikeStatusDTO(
            artworkId: artworkId.uuidString,
            likeCount: likeCount,
            isLikedByMe: myLike != nil
        )
    }

    // POST /api/v1/artworks/:artworkId/like (toggle)
    func toggleLike(req: Request) async throws -> LikeStatusDTO {
        let userId = try req.auth.require(UUID.self)
        guard let artworkId = req.parameters.get("artworkId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid artwork ID")
        }

        let existing = try await (req.db as! SQLDatabase).raw(
            "SELECT 1 FROM likes WHERE user_id = \(bind: userId) AND artwork_id = \(bind: artworkId)"
        ).first()

        if existing != nil {
            try await (req.db as! SQLDatabase).raw(
                "DELETE FROM likes WHERE user_id = \(bind: userId) AND artwork_id = \(bind: artworkId)"
            ).run()
        } else {
            try await (req.db as! SQLDatabase).raw(
                "INSERT INTO likes (user_id, artwork_id) VALUES (\(bind: userId), \(bind: artworkId))"
            ).run()
        }

        // Return updated status
        let countRow = try await (req.db as! SQLDatabase).raw("SELECT COUNT(*) AS cnt FROM likes WHERE artwork_id = \(bind: artworkId)")
            .first()
        let likeCount = try countRow?.decode(column: "cnt", as: Int.self) ?? 0

        return LikeStatusDTO(
            artworkId: artworkId.uuidString,
            likeCount: likeCount,
            isLikedByMe: existing == nil  // toggled
        )
    }

    // MARK: - Follows

    // GET /api/v1/users/:userId/profile
    func getUserProfile(req: Request) async throws -> UserProfileDTO {
        let myUserId = try req.auth.require(UUID.self)
        guard let userId = req.parameters.get("userId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid user ID")
        }

        guard let user = try await UserModel.find(userId, on: req.db) else {
            throw Abort(.notFound, reason: "User not found")
        }

        let followersRow = try await (req.db as! SQLDatabase).raw("SELECT COUNT(*) AS cnt FROM follows WHERE following_id = \(bind: userId)").first()
        let followersCount = try followersRow?.decode(column: "cnt", as: Int.self) ?? 0

        let followingRow = try await (req.db as! SQLDatabase).raw("SELECT COUNT(*) AS cnt FROM follows WHERE follower_id = \(bind: userId)").first()
        let followingCount = try followingRow?.decode(column: "cnt", as: Int.self) ?? 0

        let artworksRow = try await (req.db as! SQLDatabase).raw("SELECT COUNT(*) AS cnt FROM artworks WHERE creator_id = \(bind: userId)").first()
        let artworksCount = try artworksRow?.decode(column: "cnt", as: Int.self) ?? 0

        let isFollowing = try await (req.db as! SQLDatabase).raw(
            "SELECT 1 FROM follows WHERE follower_id = \(bind: myUserId) AND following_id = \(bind: userId)"
        ).first()

        return UserProfileDTO(
            id: user.id?.uuidString ?? "",
            username: user.username,
            displayName: user.displayName,
            avatarUrl: user.avatarUrl,
            bio: user.bio,
            followersCount: followersCount,
            followingCount: followingCount,
            artworksCount: artworksCount,
            isFollowedByMe: isFollowing != nil
        )
    }

    // POST /api/v1/users/:userId/follow (toggle)
    func toggleFollow(req: Request) async throws -> FollowStatusDTO {
        let myUserId = try req.auth.require(UUID.self)
        guard let userId = req.parameters.get("userId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid user ID")
        }

        guard myUserId != userId else {
            throw Abort(.badRequest, reason: "Cannot follow yourself")
        }

        let existing = try await (req.db as! SQLDatabase).raw(
            "SELECT 1 FROM follows WHERE follower_id = \(bind: myUserId) AND following_id = \(bind: userId)"
        ).first()

        if existing != nil {
            try await (req.db as! SQLDatabase).raw(
                "DELETE FROM follows WHERE follower_id = \(bind: myUserId) AND following_id = \(bind: userId)"
            ).run()
        } else {
            try await (req.db as! SQLDatabase).raw(
                "INSERT INTO follows (follower_id, following_id) VALUES (\(bind: myUserId), \(bind: userId))"
            ).run()
        }

        let followersRow = try await (req.db as! SQLDatabase).raw("SELECT COUNT(*) AS cnt FROM follows WHERE following_id = \(bind: userId)").first()
        let followersCount = try followersRow?.decode(column: "cnt", as: Int.self) ?? 0

        let followingRow = try await (req.db as! SQLDatabase).raw("SELECT COUNT(*) AS cnt FROM follows WHERE follower_id = \(bind: userId)").first()
        let followingCount = try followingRow?.decode(column: "cnt", as: Int.self) ?? 0

        return FollowStatusDTO(
            userId: userId.uuidString,
            followersCount: followersCount,
            followingCount: followingCount,
            isFollowedByMe: existing == nil  // toggled
        )
    }

    // GET /api/v1/users/me/following
    func getFollowing(req: Request) async throws -> [UserDTO] {
        let userId = try req.auth.require(UUID.self)

        let rows = try await (req.db as! SQLDatabase).raw("""
            SELECT u.id, u.username, u.display_name, u.wallet_address, u.bio, u.balance, u.avatar_url
            FROM users u
            INNER JOIN follows f ON f.following_id = u.id
            WHERE f.follower_id = \(bind: userId)
            ORDER BY f.created_at DESC
        """).all()

        return try rows.map { row in
            UserDTO(
                id: try row.decode(column: "id", as: UUID.self).uuidString,
                username: try row.decode(column: "username", as: String.self),
                displayName: try row.decode(column: "display_name", as: String.self),
                walletAddress: try row.decode(column: "wallet_address", as: String.self),
                bio: try? row.decode(column: "bio", as: String.self),
                balance: try row.decode(column: "balance", as: Double.self),
                avatarUrl: try? row.decode(column: "avatar_url", as: String.self)
            )
        }
    }

    // GET /api/v1/users/me/followers
    func getFollowers(req: Request) async throws -> [UserDTO] {
        let userId = try req.auth.require(UUID.self)

        let rows = try await (req.db as! SQLDatabase).raw("""
            SELECT u.id, u.username, u.display_name, u.wallet_address, u.bio, u.balance, u.avatar_url
            FROM users u
            INNER JOIN follows f ON f.follower_id = u.id
            WHERE f.following_id = \(bind: userId)
            ORDER BY f.created_at DESC
        """).all()

        return try rows.map { row in
            UserDTO(
                id: try row.decode(column: "id", as: UUID.self).uuidString,
                username: try row.decode(column: "username", as: String.self),
                displayName: try row.decode(column: "display_name", as: String.self),
                walletAddress: try row.decode(column: "wallet_address", as: String.self),
                bio: try? row.decode(column: "bio", as: String.self),
                balance: try row.decode(column: "balance", as: Double.self),
                avatarUrl: try? row.decode(column: "avatar_url", as: String.self)
            )
        }
    }
}
