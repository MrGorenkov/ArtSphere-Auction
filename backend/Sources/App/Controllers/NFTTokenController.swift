import Vapor
import Fluent

struct NFTTokenController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let nft = routes.grouped("nft")
        nft.post("mint", use: mintNFT)
    }

    // POST /api/v1/nft/mint
    func mintNFT(req: Request) async throws -> NFTTokenDTO {
        let user = try req.auth.require(UserModel.self)
        let userId = try user.requireID()
        let body = try req.content.decode(MintNFTRequest.self)

        guard let artworkId = UUID(uuidString: body.artworkId) else {
            throw Abort(.badRequest, reason: "Invalid artwork ID")
        }

        // Проверяем, существует ли работа
        guard let artwork = try await ArtworkModel.find(artworkId, on: req.db) else {
            throw Abort(.notFound, reason: "Artwork not found")
        }

        // Проверяем, не сминтили ли её уже
        if let _ = try await NFTTokenModel.query(on: req.db)
            .filter(\.$artwork.$id == artworkId)
            .first() {
            throw Abort(.badRequest, reason: "NFT for this artwork already exists")
        }

        // ВАЖНО: Ниже мы пока ставим плейсхолдер. 
        // Когда ты задеплоишь реальную коллекцию на Шаге 2, сюда нужно будет вставить её адрес!
        let collectionAddress = "EQCYoGV2OPqa3wgVF8Ac7lDs25Ifz9ImJylMHFIX7uS3hpiJ"
        let generatedTokenId = String(Int.random(in: 1000...999999)) // Имитация ID токена в блокчейне

        let token = NFTTokenModel(
            artworkId: artworkId,
            ownerId: userId,
            contractAddress: collectionAddress,
            tokenIdOnChain: generatedTokenId,
            blockchain: "TON",
            status: "minted"
        )

        try await token.save(on: req.db)

        // Генерируем фейковый URI для метаданных на базе MinIO
        token.metadataUri = "\(APIConfig.baseURL)/metadata/\(generatedTokenId).json"
        try await token.save(on: req.db)

        return NFTTokenDTO(
            id: try token.requireID().uuidString,
            artworkId: artworkId.uuidString,
            ownerId: userId.uuidString,
            contractAddress: collectionAddress,
            tokenIdOnChain: generatedTokenId,
            blockchain: token.blockchain,
            status: token.status,
            mintedAt: ISO8601DateFormatter().string(from: token.mintedAt ?? Date()),
            metadataUri: token.metadataUri
        )
    }
}