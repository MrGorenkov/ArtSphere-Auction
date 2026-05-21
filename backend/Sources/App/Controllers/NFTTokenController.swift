import Vapor
import Fluent

struct NFTTokenController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let nft = routes.grouped("nft")
        nft.post("mint", use: mintNFT)
    }

    // POST /api/v1/nft/mint
    func mintNFT(req: Request) async throws -> NFTTokenDTO {
        let userId = try req.auth.require(UUID.self)
        let body = try req.content.decode(MintNFTRequest.self)

        guard let artworkId = UUID(uuidString: body.artworkId) else {
            throw Abort(.badRequest, reason: "Invalid artwork ID")
        }

        guard let _ = try await ArtworkModel.find(artworkId, on: req.db) else {
            throw Abort(.notFound, reason: "Artwork not found")
        }

        if let _ = try await NFTTokenModel.query(on: req.db)
            .filter(\.$artwork.$id == artworkId)
            .first() {
            throw Abort(.badRequest, reason: "NFT for this artwork already exists")
        }

        // Реальный mint в TON Testnet: HTTP-вызов в minter-сервис.
        // Сервис подписывает MintNFT-сообщение mnemonic-ом owner-кошелька и шлёт
        // его в задеплоенный контракт ArtSphereCollection. Контракт инкрементит
        // next_item_index — это и есть on-chain tokenId, который мы сохраним.
        let mintResult = try await callMinter(artworkId: artworkId.uuidString, client: req.client, logger: req.logger)

        let token = NFTTokenModel(
            artworkId: artworkId,
            ownerId: userId,
            contractAddress: mintResult.collection,
            tokenIdOnChain: mintResult.tokenId,
            blockchain: "TON",
            status: "minted"
        )
        try await token.save(on: req.db)

        // metadataUri — прямая ссылка на mint-транзакцию в эксплорере (если есть hash),
        // иначе fallback на адрес коллекции (страница со всеми transactions).
        if let hash = mintResult.txHash, !hash.isEmpty {
            token.metadataUri = "https://testnet.tonviewer.com/transaction/\(hash)"
        } else {
            token.metadataUri = "https://testnet.tonviewer.com/\(mintResult.collection)"
        }
        try await token.save(on: req.db)

        // Creator-rewards: бонус за mint + milestone-бонусы (5/15/30 работ).
        if let creator = try await UserModel.find(userId, on: req.db) {
            try await RewardsEngine.onMint(user: creator, on: req.db)
        }

        return NFTTokenDTO(
            id: try token.requireID().uuidString,
            artworkId: artworkId.uuidString,
            ownerId: userId.uuidString,
            contractAddress: mintResult.collection,
            tokenIdOnChain: mintResult.tokenId,
            blockchain: token.blockchain,
            status: token.status,
            mintedAt: ISO8601DateFormatter().string(from: token.mintedAt ?? Date()),
            metadataUri: token.metadataUri
        )
    }

    // MARK: - Minter client

    private struct MinterRequest: Content {
        let artworkId: String
    }

    private struct MinterResponse: Content {
        let tokenId: String
        let collection: String
        let artworkId: String
        let txHash: String?
    }

    private struct MinterError: Content {
        let error: String
    }

    private func callMinter(artworkId: String, client: Client, logger: Logger) async throws -> MinterResponse {
        let baseUrl = Environment.get("MINTER_URL") ?? "http://minter:3001"
        let uri = URI(string: "\(baseUrl)/mint")

        let response = try await client.post(uri) { req in
            try req.content.encode(MinterRequest(artworkId: artworkId))
        }

        guard response.status == .ok else {
            let message = (try? response.content.decode(MinterError.self).error) ?? "status \(response.status.code)"
            logger.error("minter returned non-ok: \(message)")
            throw Abort(.internalServerError, reason: "TON mint failed: \(message)")
        }

        do {
            return try response.content.decode(MinterResponse.self)
        } catch {
            throw Abort(.internalServerError, reason: "TON mint: invalid response from minter")
        }
    }
}
