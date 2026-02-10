import Vapor
import Fluent

struct NFTTokenController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let nft = routes.grouped("nft")
        nft.get(use: myTokens)
        nft.post("mint", use: mint)
        nft.get(":tokenId", use: show)
    }

    // GET /api/v1/nft — мои NFT токены
    func myTokens(req: Request) async throws -> [NFTTokenDTO] {
        let userId = try req.auth.require(UUID.self)

        let tokens = try await NFTTokenModel.query(on: req.db)
            .filter(\.$owner.$id == userId)
            .sort(\.$mintedAt, .descending)
            .all()

        return tokens.map { $0.toDTO() }
    }

    // GET /api/v1/nft/:tokenId
    func show(req: Request) async throws -> NFTTokenDTO {
        guard let tokenId = req.parameters.get("tokenId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid token ID")
        }

        guard let token = try await NFTTokenModel.find(tokenId, on: req.db) else {
            throw Abort(.notFound, reason: "NFT token not found")
        }

        return token.toDTO()
    }

    // POST /api/v1/nft/mint — создать NFT из произведения
    func mint(req: Request) async throws -> NFTTokenDTO {
        let userId = try req.auth.require(UUID.self)
        let body = try req.content.decode(MintNFTRequest.self)

        guard let artworkId = UUID(uuidString: body.artworkId) else {
            throw Abort(.badRequest, reason: "Invalid artwork ID")
        }

        guard let artwork = try await ArtworkModel.find(artworkId, on: req.db) else {
            throw Abort(.notFound, reason: "Artwork not found")
        }

        guard artwork.$creator.id == userId else {
            throw Abort(.forbidden, reason: "You can only mint your own artworks")
        }

        // Генерация адреса контракта (симуляция)
        let contractAddress = "0x" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(40)
        let tokenIdOnChain = String(Int.random(in: 1...999999))

        let token = NFTTokenModel(
            artworkId: artworkId,
            ownerId: userId,
            contractAddress: String(contractAddress),
            tokenIdOnChain: tokenIdOnChain,
            blockchain: body.blockchain ?? artwork.blockchain,
            status: "minted"
        )

        try await token.save(on: req.db)
        return token.toDTO()
    }
}
