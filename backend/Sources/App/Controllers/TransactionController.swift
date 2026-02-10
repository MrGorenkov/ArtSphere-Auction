import Vapor
import Fluent

struct TransactionController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let tx = routes.grouped("transactions")
        tx.get(use: myTransactions)
        tx.get(":txId", use: show)
    }

    // GET /api/v1/transactions — мои транзакции (покупки и продажи)
    func myTransactions(req: Request) async throws -> [TransactionDTO] {
        let userId = try req.auth.require(UUID.self)

        let transactions = try await TransactionModel.query(on: req.db)
            .group(.or) { group in
                group.filter(\.$buyer.$id == userId)
                group.filter(\.$seller.$id == userId)
            }
            .sort(\.$createdAt, .descending)
            .all()

        return transactions.map { $0.toDTO() }
    }

    // GET /api/v1/transactions/:txId
    func show(req: Request) async throws -> TransactionDTO {
        guard let txId = req.parameters.get("txId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid transaction ID")
        }

        guard let tx = try await TransactionModel.find(txId, on: req.db) else {
            throw Abort(.notFound, reason: "Transaction not found")
        }

        return tx.toDTO()
    }
}
