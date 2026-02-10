import Vapor
import Fluent

struct AuthController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let auth = routes.grouped("auth")
        auth.post("register", use: register)
        auth.post("login", use: login)
    }

    // POST /api/v1/auth/register
    func register(req: Request) async throws -> LoginResponse {
        try RegisterRequest.validate(content: req)
        let body = try req.content.decode(RegisterRequest.self)

        // Check if username or wallet already exists
        let existingUser = try await UserModel.query(on: req.db)
            .group(.or) { group in
                group.filter(\.$username == body.username)
                group.filter(\.$walletAddress == body.walletAddress)
            }
            .first()

        guard existingUser == nil else {
            throw Abort(.conflict, reason: "Username or wallet address already registered")
        }

        let passwordHash = try Bcrypt.hash(body.password)
        let user = UserModel(
            username: body.username,
            displayName: body.displayName,
            email: body.email,
            walletAddress: body.walletAddress,
            passwordHash: passwordHash
        )

        try await user.save(on: req.db)

        // Create default collection
        let defaultCollection = CollectionModel(
            userId: user.id!,
            name: "Моя коллекция",
            description: "",
            isDefault: true
        )
        try await defaultCollection.save(on: req.db)

        // Generate JWT
        let token = try generateToken(for: user, on: req)

        return LoginResponse(token: token, user: user.toDTO())
    }

    // POST /api/v1/auth/login
    func login(req: Request) async throws -> LoginResponse {
        let body = try req.content.decode(LoginRequest.self)

        guard let user = try await UserModel.query(on: req.db)
            .filter(\.$walletAddress == body.walletAddress)
            .first()
        else {
            throw Abort(.unauthorized, reason: "Invalid credentials")
        }

        guard try Bcrypt.verify(body.password, created: user.passwordHash) else {
            throw Abort(.unauthorized, reason: "Invalid credentials")
        }

        let token = try generateToken(for: user, on: req)

        return LoginResponse(token: token, user: user.toDTO())
    }

    private func generateToken(for user: UserModel, on req: Request) throws -> String {
        let payload = JWTPayload(
            subject: .init(value: user.id!.uuidString),
            expiration: .init(value: Date().addingTimeInterval(86400 * 7)) // 7 days
        )
        return try req.jwt.sign(payload)
    }
}
