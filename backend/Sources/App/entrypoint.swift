import Vapor
import Fluent
import FluentPostgresDriver

@main
struct NFTArtsBackend {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)

        let app = try await Application.make(env)

        // Configure database — supports both Railway DATABASE_URL and individual vars
        if let dbUrl = Environment.get("DATABASE_URL") {
            // Railway provides a single connection URL
            try app.databases.use(.postgres(url: dbUrl), as: .psql)
        } else {
            let dbHost = Environment.get("DATABASE_HOST") ?? "localhost"
            let dbPort = Environment.get("DATABASE_PORT").flatMap(Int.init) ?? 5432
            let dbUser = Environment.get("DATABASE_USERNAME") ?? "nftarts"
            let dbPass = Environment.get("DATABASE_PASSWORD") ?? "nftarts_secret"
            let dbName = Environment.get("DATABASE_NAME") ?? "nftarts_db"
            app.databases.use(.postgres(
                hostname: dbHost, port: dbPort,
                username: dbUser, password: dbPass,
                database: dbName
            ), as: .psql)
        }

        // Configure JWT
        let jwtSecret = Environment.get("JWT_SECRET") ?? "dev-secret-key"
        app.jwt.signers.use(.hs256(key: jwtSecret))

        // Configure CORS
        let corsConfig = CORSMiddleware.Configuration(
            allowedOrigin: .all,
            allowedMethods: [.GET, .POST, .PUT, .PATCH, .DELETE, .OPTIONS],
            allowedHeaders: [.accept, .authorization, .contentType, .origin]
        )
        app.middleware.use(CORSMiddleware(configuration: corsConfig))

        // Register routes
        try routes(app)

        try await app.execute()
    }
}
