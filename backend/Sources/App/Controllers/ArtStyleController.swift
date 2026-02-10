import Vapor
import Fluent

struct ArtStyleController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let styles = routes.grouped("styles")
        styles.get(use: index)
        styles.get(":styleId", "artworks", use: artworksByStyle)
    }

    // GET /api/v1/styles
    func index(req: Request) async throws -> [ArtStyleDTO] {
        let styles = try await ArtStyleModel.query(on: req.db)
            .with(\.$artworks)
            .all()

        return styles.map { $0.toDTO() }
    }

    // GET /api/v1/styles/:styleId/artworks
    func artworksByStyle(req: Request) async throws -> [ArtworkDTO] {
        guard let styleId = req.parameters.get("styleId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid style ID")
        }

        let artworks = try await ArtworkModel.query(on: req.db)
            .filter(\.$style.$id == styleId)
            .filter(\.$isPublished == true)
            .with(\.$style)
            .sort(\.$createdAt, .descending)
            .all()

        return artworks.map { $0.toDTO() }
    }
}
