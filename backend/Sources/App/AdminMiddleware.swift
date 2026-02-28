import Vapor
import Fluent

struct AdminMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let userId = try request.auth.require(UUID.self)

        guard let user = try await UserModel.find(userId, on: request.db) else {
            throw Abort(.unauthorized, reason: "User not found")
        }

        guard user.isAdmin else {
            throw Abort(.forbidden, reason: "Admin access required")
        }

        return try await next.respond(to: request)
    }
}
