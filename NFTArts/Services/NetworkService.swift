import Foundation

// MARK: - API Configuration

enum APIConfig {
    static var baseURL: String {
        #if DEBUG
        return "http://localhost:8080/api/v1"
        #else
        return "https://api.nftarts.com/api/v1"
        #endif
    }

    static let timeout: TimeInterval = 30
}

// MARK: - API Error

enum APIError: LocalizedError {
    case invalidURL
    case noData
    case decodingError(Error)
    case serverError(Int, String)
    case networkError(Error)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .noData: return "No data received"
        case .decodingError(let error): return "Decoding error: \(error.localizedDescription)"
        case .serverError(let code, let message): return "Server error \(code): \(message)"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .unauthorized: return "Unauthorized. Please log in again."
        }
    }
}

// MARK: - Network Service

final class NetworkService {
    static let shared = NetworkService()

    private let session: URLSession
    private var authToken: String?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = APIConfig.timeout
        config.httpAdditionalHeaders = [
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]
        self.session = URLSession(configuration: config)
    }

    func setAuthToken(_ token: String) {
        self.authToken = token
    }

    // MARK: - Generic Request

    func request<T: Decodable>(
        endpoint: String,
        method: HTTPMethod = .get,
        body: Encodable? = nil
    ) async throws -> T {
        guard let url = URL(string: "\(APIConfig.baseURL)/\(endpoint)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.noData
        }

        switch httpResponse.statusCode {
        case 200...299:
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decodingError(error)
            }
        case 401:
            throw APIError.unauthorized
        default:
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.serverError(httpResponse.statusCode, message)
        }
    }

    enum HTTPMethod: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case patch = "PATCH"
        case delete = "DELETE"
    }
}

// MARK: - API Models (for PostgreSQL backend)

struct APIArtwork: Codable {
    let id: String
    let title: String
    let artistName: String
    let description: String
    let imageUrl: String?
    let category: String
    let tokenId: String?
    let contractAddress: String?
    let blockchain: String
    let createdAt: String
}

struct APIAuction: Codable {
    let id: String
    let artworkId: String
    let startTime: String
    let endTime: String
    let currentBid: Double
    let startingPrice: Double
    let reservePrice: Double?
    let status: String
    let winnerId: String?
    let creatorId: String?
}

struct APIBid: Codable {
    let id: String
    let auctionId: String
    let userId: String
    let userName: String
    let amount: Double
    let timestamp: String
}

struct APIUser: Codable {
    let id: String
    let username: String
    let displayName: String
    let walletAddress: String
    let bio: String?
    let balance: Double
    let avatarUrl: String?
}

struct APICollection: Codable {
    let id: String
    let name: String
    let description: String?
    let artworkIds: [String]
    let userId: String
    let createdAt: String
    let updatedAt: String
}

struct APILoginRequest: Codable {
    let walletAddress: String
    let signature: String
}

struct APILoginResponse: Codable {
    let token: String
    let user: APIUser
}

struct APIBidRequest: Codable {
    let auctionId: String
    let amount: Double
}

struct APICreateAuctionRequest: Codable {
    let artworkId: String
    let startingPrice: Double
    let reservePrice: Double?
    let durationHours: Int
}

// MARK: - API Endpoints

extension NetworkService {
    // Artworks
    func fetchArtworks() async throws -> [APIArtwork] {
        try await request(endpoint: "artworks")
    }

    func fetchArtwork(id: String) async throws -> APIArtwork {
        try await request(endpoint: "artworks/\(id)")
    }

    func uploadArtwork(imageData: Data, metadata: APIArtwork) async throws -> APIArtwork {
        try await request(endpoint: "artworks", method: .post, body: metadata)
    }

    // Auctions
    func fetchAuctions() async throws -> [APIAuction] {
        try await request(endpoint: "auctions")
    }

    func fetchAuction(id: String) async throws -> APIAuction {
        try await request(endpoint: "auctions/\(id)")
    }

    func createAuction(request body: APICreateAuctionRequest) async throws -> APIAuction {
        try await request(endpoint: "auctions", method: .post, body: body)
    }

    // Bids
    func fetchBids(auctionId: String) async throws -> [APIBid] {
        try await request(endpoint: "auctions/\(auctionId)/bids")
    }

    func placeBid(request body: APIBidRequest) async throws -> APIBid {
        try await request(endpoint: "bids", method: .post, body: body)
    }

    // User
    func fetchProfile() async throws -> APIUser {
        try await request(endpoint: "users/me")
    }

    func login(request body: APILoginRequest) async throws -> APILoginResponse {
        try await request(endpoint: "auth/login", method: .post, body: body)
    }

    // Collections
    func fetchCollections() async throws -> [APICollection] {
        try await request(endpoint: "collections")
    }

    func createCollection(name: String, description: String) async throws -> APICollection {
        struct Body: Codable { let name: String; let description: String }
        return try await request(endpoint: "collections", method: .post, body: Body(name: name, description: description))
    }
}
