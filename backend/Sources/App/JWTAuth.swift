import Vapor
import JWT

// MARK: - JWT Payload

struct JWTPayload: JWT.JWTPayload {
    var subject: SubjectClaim
    var expiration: ExpirationClaim

    func verify(using signer: JWTSigner) throws {
        try self.expiration.verifyNotExpired()
    }
}

// MARK: - JWT Auth Middleware

struct JWTAuthMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let token = request.headers.bearerAuthorization?.token else {
            throw Abort(.unauthorized, reason: "Missing authorization token")
        }

        let payload = try request.jwt.verify(token, as: JWTPayload.self)

        guard let userId = UUID(uuidString: payload.subject.value) else {
            throw Abort(.unauthorized, reason: "Invalid token payload")
        }

        // Store user ID for controllers
        request.auth.login(userId)

        return try await next.respond(to: request)
    }
}

// MARK: - UUID Authenticatable

extension UUID: Authenticatable {}
