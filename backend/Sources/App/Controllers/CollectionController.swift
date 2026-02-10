import Vapor
import Fluent

struct CollectionController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let collections = routes.grouped("collections")
        collections.get(use: index)
        collections.post(use: create)
        collections.put(":collectionId", use: update)
        collections.delete(":collectionId", use: delete)
        collections.post(":collectionId", "artworks", use: addArtwork)
        collections.delete(":collectionId", "artworks", ":artworkId", use: removeArtwork)
    }

    // GET /api/v1/collections
    func index(req: Request) async throws -> [CollectionDTO] {
        let userId = try req.auth.require(UUID.self)

        let collections = try await CollectionModel.query(on: req.db)
            .filter(\.$user.$id == userId)
            .with(\.$artworks)
            .sort(\.$createdAt, .ascending)
            .all()

        return collections.map { collection in
            let artworkIds = collection.artworks.compactMap { $0.id?.uuidString }
            return collection.toDTO(artworkIds: artworkIds)
        }
    }

    // POST /api/v1/collections
    func create(req: Request) async throws -> CollectionDTO {
        let userId = try req.auth.require(UUID.self)
        let body = try req.content.decode(CreateCollectionRequest.self)

        let collection = CollectionModel(
            userId: userId,
            name: body.name,
            description: body.description ?? "",
            isPrivate: body.isPrivate ?? false
        )

        try await collection.save(on: req.db)
        return collection.toDTO()
    }

    // PUT /api/v1/collections/:collectionId
    func update(req: Request) async throws -> CollectionDTO {
        let userId = try req.auth.require(UUID.self)

        guard let collectionId = req.parameters.get("collectionId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid collection ID")
        }

        guard let collection = try await CollectionModel.find(collectionId, on: req.db) else {
            throw Abort(.notFound, reason: "Collection not found")
        }

        guard collection.$user.id == userId else {
            throw Abort(.forbidden, reason: "Not your collection")
        }

        let body = try req.content.decode(UpdateCollectionRequest.self)

        if let name = body.name { collection.name = name }
        if let description = body.description { collection.description = description }
        if let isPrivate = body.isPrivate { collection.isPrivate = isPrivate }

        try await collection.save(on: req.db)
        return collection.toDTO()
    }

    // DELETE /api/v1/collections/:collectionId
    func delete(req: Request) async throws -> HTTPStatus {
        let userId = try req.auth.require(UUID.self)

        guard let collectionId = req.parameters.get("collectionId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid collection ID")
        }

        guard let collection = try await CollectionModel.find(collectionId, on: req.db) else {
            throw Abort(.notFound, reason: "Collection not found")
        }

        guard collection.$user.id == userId else {
            throw Abort(.forbidden, reason: "Not your collection")
        }

        guard !collection.isDefault else {
            throw Abort(.badRequest, reason: "Cannot delete default collection")
        }

        try await collection.delete(on: req.db)
        return .noContent
    }

    // POST /api/v1/collections/:collectionId/artworks
    func addArtwork(req: Request) async throws -> HTTPStatus {
        let userId = try req.auth.require(UUID.self)
        let body = try req.content.decode(CollectionArtworkRequest.self)

        guard let collectionId = req.parameters.get("collectionId", as: UUID.self),
              let artworkId = UUID(uuidString: body.artworkId) else {
            throw Abort(.badRequest, reason: "Invalid IDs")
        }

        guard let collection = try await CollectionModel.find(collectionId, on: req.db) else {
            throw Abort(.notFound, reason: "Collection not found")
        }

        guard collection.$user.id == userId else {
            throw Abort(.forbidden, reason: "Not your collection")
        }

        let pivot = CollectionArtworkPivot(
            collectionId: collectionId,
            artworkId: artworkId,
            position: body.position ?? 0,
            userNote: body.userNote ?? ""
        )
        try await pivot.save(on: req.db)

        return .created
    }

    // DELETE /api/v1/collections/:collectionId/artworks/:artworkId
    func removeArtwork(req: Request) async throws -> HTTPStatus {
        let userId = try req.auth.require(UUID.self)

        guard let collectionId = req.parameters.get("collectionId", as: UUID.self),
              let artworkId = req.parameters.get("artworkId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid IDs")
        }

        guard let collection = try await CollectionModel.find(collectionId, on: req.db) else {
            throw Abort(.notFound, reason: "Collection not found")
        }

        guard collection.$user.id == userId else {
            throw Abort(.forbidden, reason: "Not your collection")
        }

        try await CollectionArtworkPivot.query(on: req.db)
            .filter(\.$collection.$id == collectionId)
            .filter(\.$artwork.$id == artworkId)
            .delete()

        return .noContent
    }
}
