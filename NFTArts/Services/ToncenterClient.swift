import Foundation

/// Минимальный клиент к публичному testnet Toncenter API v3.
/// Без API-key справляется в рамках demo: лимит ~1 запрос/сек на IP.
/// Документация: https://testnet.toncenter.com/api/v3/
enum ToncenterClient {

    static let baseURL = "https://testnet.toncenter.com/api/v3"

    enum Error: Swift.Error, LocalizedError {
        case invalidURL
        case invalidResponse(Int)
        case decodingFailed
        case noAccount

        var errorDescription: String? {
            switch self {
            case .invalidURL:           return "Некорректный URL"
            case .invalidResponse(let c): return "Сервер вернул статус \(c)"
            case .decodingFailed:       return "Не удалось распарсить ответ"
            case .noAccount:            return "Аккаунт не найден в блокчейне"
            }
        }
    }

    // MARK: - Balance

    /// Возвращает баланс в нанотонах (1 TON = 1e9 nano).
    static func fetchBalance(address: String) async throws -> UInt64 {
        guard let escaped = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/accountStates?address=\(escaped)") else {
            throw Error.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw Error.invalidResponse(0) }
        guard http.statusCode == 200 else { throw Error.invalidResponse(http.statusCode) }

        let decoded: AccountStatesResponse
        do {
            decoded = try JSONDecoder().decode(AccountStatesResponse.self, from: data)
        } catch {
            throw Error.decodingFailed
        }

        // Если кошелёк ещё ни разу не получал переводов, account отсутствует.
        guard let first = decoded.accounts.first, let raw = first.balance,
              let nano = UInt64(raw) else {
            return 0
        }
        return nano
    }

    // MARK: - Transactions (recent activity)

    /// История последних N транзакций по адресу.
    static func fetchTransactions(address: String, limit: Int = 10) async throws -> [TONTransaction] {
        guard let escaped = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/transactions?account=\(escaped)&limit=\(limit)") else {
            throw Error.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw Error.invalidResponse((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        do {
            let decoded = try JSONDecoder().decode(TransactionsResponse.self, from: data)
            return decoded.transactions
        } catch {
            throw Error.decodingFailed
        }
    }
}

// MARK: - DTOs

private struct AccountStatesResponse: Decodable {
    let accounts: [AccountState]
    struct AccountState: Decodable {
        let balance: String?
    }
}

private struct TransactionsResponse: Decodable {
    let transactions: [TONTransaction]
}

struct TONTransaction: Decodable, Identifiable {
    let hash: String
    let now: TimeInterval?
    let totalFees: String?

    var id: String { hash }
    var date: Date? { now.map { Date(timeIntervalSince1970: $0) } }
    var feeTON: Double? {
        guard let raw = totalFees, let nano = UInt64(raw) else { return nil }
        return Double(nano) / 1_000_000_000.0
    }

    enum CodingKeys: String, CodingKey {
        case hash, now
        case totalFees = "total_fees"
    }
}
