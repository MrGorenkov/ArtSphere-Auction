import Vapor
import Fluent

struct ArtworkController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let artworks = routes.grouped("artworks")
        artworks.get(use: index)
        artworks.get(":artworkId", use: show)
        artworks.post(use: create)
        artworks.get(":artworkId", "3d", use: get3DModels)
        artworks.on(.POST, ":artworkId", "upload-image", body: .collect(maxSize: "20mb"), use: uploadImage)
    }

    // GET /api/v1/artworks?style_id=...&search=...&blockchain=...
    func index(req: Request) async throws -> [ArtworkDTO] {
        let styleId = req.query[UUID.self, at: "style_id"]
        let search = req.query[String.self, at: "search"]
        let blockchain = req.query[String.self, at: "blockchain"]

        var query = ArtworkModel.query(on: req.db)
            .filter(\.$isPublished == true)
            .with(\.$style)

        if let styleId = styleId {
            query = query.filter(\.$style.$id == styleId)
        }

        if let blockchain = blockchain {
            query = query.filter(\.$blockchain == blockchain)
        }

        if let search = search {
            query = query.group(.or) { group in
                group.filter(\.$title, .custom("ILIKE"), "%\(search)%")
                group.filter(\.$artistName, .custom("ILIKE"), "%\(search)%")
            }
        }

        let artworks = try await query
            .sort(\.$createdAt, .descending)
            .all()

        // Подтягиваем on-chain метаданные пачкой (LEFT JOIN nft_tokens).
        let tokenMap = try await Self.loadTokenMap(for: artworks.compactMap { $0.id }, on: req.db)
        return artworks.map { artwork in
            let token = artwork.id.flatMap { tokenMap[$0] }
            return artwork.toDTO(
                tokenIdOnChain: token?.tokenId,
                contractAddress: token?.contract,
                explorerUrl: token?.explorerUrl
            )
        }
    }

    /// Возвращает мапу artworkId → on-chain метаданные за один запрос.
    /// tokenId опциональный — если контракт ещё не успел инкрементить counter, поле nil.
    static func loadTokenMap(for artworkIds: [UUID], on db: Database) async throws -> [UUID: (tokenId: String?, contract: String, explorerUrl: String?)] {
        guard !artworkIds.isEmpty else { return [:] }
        let tokens = try await NFTTokenModel.query(on: db)
            .filter(\.$artwork.$id ~~ artworkIds)
            .all()
        var map: [UUID: (tokenId: String?, contract: String, explorerUrl: String?)] = [:]
        for token in tokens {
            map[token.$artwork.id] = (tokenId: token.tokenIdOnChain, contract: token.contractAddress, explorerUrl: token.metadataUri)
        }
        return map
    }

    // GET /api/v1/artworks/:artworkId
    func show(req: Request) async throws -> ArtworkDTO {
        guard let artworkId = req.parameters.get("artworkId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid artwork ID")
        }

        guard let artwork = try await ArtworkModel.query(on: req.db)
            .filter(\.$id == artworkId)
            .with(\.$style)
            .first()
        else {
            throw Abort(.notFound, reason: "Artwork not found")
        }

        let tokenMap = try await Self.loadTokenMap(for: [artworkId], on: req.db)
        let token = tokenMap[artworkId]
        return artwork.toDTO(tokenIdOnChain: token?.tokenId, contractAddress: token?.contract, explorerUrl: token?.explorerUrl)
    }

    // POST /api/v1/artworks
    func create(req: Request) async throws -> ArtworkDTO {
        let userId = try req.auth.require(UUID.self)
        let body = try req.content.decode(CreateArtworkRequest.self)

        guard let user = try await UserModel.find(userId, on: req.db) else {
            throw Abort(.notFound, reason: "User not found")
        }

        let styleId = body.styleId.flatMap { UUID(uuidString: $0) }

        let artwork = ArtworkModel(
            title: body.title,
            artistName: user.displayName,
            description: body.description ?? "",
            price: body.price,
            styleId: styleId,
            blockchain: body.blockchain ?? "TON",
            creatorId: userId
        )

        try await artwork.save(on: req.db)
        return artwork.toDTO()
    }

    // GET /api/v1/artworks/:artworkId/3d
    func get3DModels(req: Request) async throws -> [Visualization3DDTO] {
        guard let artworkId = req.parameters.get("artworkId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid artwork ID")
        }

        let models = try await Visualization3DModel.query(on: req.db)
            .filter(\.$artwork.$id == artworkId)
            .all()

        return models.map { $0.toDTO() }
    }

    // POST /api/v1/artworks/:artworkId/upload-image
    func uploadImage(req: Request) async throws -> ArtworkDTO {
        let userId = try req.auth.require(UUID.self)

        guard let artworkId = req.parameters.get("artworkId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid artwork ID")
        }

        guard let artwork = try await ArtworkModel.find(artworkId, on: req.db) else {
            throw Abort(.notFound, reason: "Artwork not found")
        }

        guard artwork.$creator.id == userId else {
            throw Abort(.forbidden, reason: "Not your artwork")
        }

        // Multipart upload
        let file = try req.content.decode(FileUpload.self)
        let ext = file.file.filename.split(separator: ".").last.map(String.init) ?? "png"
        let key = "\(artworkId.uuidString).\(ext)"

        let url = try await req.minio.upload(
            data: file.file.data,
            bucket: MinIOService.artworksBucket,
            key: key,
            contentType: file.file.contentType?.description ?? "image/png",
            on: req.client
        )

        artwork.imageUrl = url
        try await artwork.save(on: req.db)
        return artwork.toDTO()
    }
}

struct FileUpload: Content {
    let file: File
}
