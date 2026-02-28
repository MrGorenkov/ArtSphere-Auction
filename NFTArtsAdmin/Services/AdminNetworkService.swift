import Foundation

class AdminNetworkService {
    static let shared = AdminNetworkService()
    private let baseURL = "http://172.20.10.2:8080/api/v1"
    var token: String?

    private init() {}

    // MARK: - Auth

    func login(walletAddress: String, password: String) async throws -> AdminLoginResponse {
        let body = AdminLoginRequest(walletAddress: walletAddress, password: password)
        let response: AdminLoginResponse = try await post(endpoint: "auth/login", body: body, auth: false)
        self.token = response.token
        return response
    }

    // MARK: - Admin API

    func fetchDashboard() async throws -> DashboardStats {
        try await get(endpoint: "admin/dashboard")
    }

    func fetchUsers() async throws -> [AdminUser] {
        try await get(endpoint: "admin/users")
    }

    func toggleUserActive(userId: String) async throws -> AdminUser {
        try await put(endpoint: "admin/users/\(userId)/toggle-active")
    }

    func deleteUser(userId: String) async throws {
        try await deleteRequest(endpoint: "admin/users/\(userId)")
    }

    func fetchArtworks() async throws -> [AdminArtwork] {
        try await get(endpoint: "admin/artworks")
    }

    func updateArtwork(id: String, update: AdminUpdateArtwork) async throws -> AdminArtwork {
        try await put(endpoint: "admin/artworks/\(id)", body: update)
    }

    func deleteArtwork(id: String) async throws {
        try await deleteRequest(endpoint: "admin/artworks/\(id)")
    }

    func fetchAuctions() async throws -> [AdminAuction] {
        try await get(endpoint: "admin/auctions")
    }

    func cancelAuction(id: String) async throws -> AdminAuction {
        try await put(endpoint: "admin/auctions/\(id)/cancel")
    }

    func fetchAuctionBids(auctionId: String) async throws -> [AdminBid] {
        try await get(endpoint: "admin/auctions/\(auctionId)/bids")
    }

    // MARK: - HTTP Helpers

    private func get<T: Decodable>(endpoint: String) async throws -> T {
        let url = URL(string: "\(baseURL)/\(endpoint)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)

        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }

    private func post<T: Decodable, B: Encodable>(endpoint: String, body: B, auth: Bool = true) async throws -> T {
        let url = URL(string: "\(baseURL)/\(endpoint)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if auth, let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)

        return try JSONDecoder().decode(T.self, from: data)
    }

    private func put<T: Decodable>(endpoint: String) async throws -> T {
        let url = URL(string: "\(baseURL)/\(endpoint)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)

        return try JSONDecoder().decode(T.self, from: data)
    }

    private func put<T: Decodable, B: Encodable>(endpoint: String, body: B) async throws -> T {
        let url = URL(string: "\(baseURL)/\(endpoint)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)

        return try JSONDecoder().decode(T.self, from: data)
    }

    private func deleteRequest(endpoint: String) async throws {
        let url = URL(string: "\(baseURL)/\(endpoint)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AdminError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AdminError.serverError(httpResponse.statusCode, message)
        }
    }
}

enum AdminError: LocalizedError {
    case invalidResponse
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid server response"
        case .serverError(let code, let msg): return "Error \(code): \(msg)"
        }
    }
}
