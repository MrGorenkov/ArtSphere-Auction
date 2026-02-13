import Foundation

// MARK: - API Configuration

enum APIConfig {
    static var baseURL: String {
        #if DEBUG
        return "http://192.168.1.54:8080/api/v1"
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

// MARK: - HTTP Method

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

// MARK: - Keychain Helper

private struct KeychainHelper {
    private static let service = "com.gorenkov.NFTArts"
    private static let account = "authToken"

    static func save(_ token: String) {
        guard let data = token.data(using: .utf8) else { return }

        // Delete old item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Network Service

final class NetworkService {
    static let shared = NetworkService()

    private let session: URLSession

    /// Auth token stored securely in Keychain.
    var authToken: String? {
        get { KeychainHelper.load() }
        set {
            if let newValue {
                KeychainHelper.save(newValue)
            } else {
                KeychainHelper.delete()
            }
        }
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = APIConfig.timeout
        config.httpAdditionalHeaders = [
            "Accept": "application/json"
        ]
        self.session = URLSession(configuration: config)

        // One-time migration from UserDefaults to Keychain
        Self.migrateTokenFromUserDefaults()
    }

    /// Convenience setter used by AuthManager and others.
    func setAuthToken(_ token: String?) {
        self.authToken = token
    }

    /// Migrates any existing token from UserDefaults into Keychain, then removes it.
    private static func migrateTokenFromUserDefaults() {
        let legacyKey = "com.nftarts.authToken"
        if let oldToken = UserDefaults.standard.string(forKey: legacyKey) {
            KeychainHelper.save(oldToken)
            UserDefaults.standard.removeObject(forKey: legacyKey)
        }
    }

    // MARK: - Generic JSON Request

    /// Sends a JSON request and decodes the response into `T`.
    func request<T: Decodable>(
        endpoint: String,
        method: HTTPMethod = .get,
        body: (any Encodable)? = nil,
        queryItems: [URLQueryItem]? = nil
    ) async throws -> T {
        guard var components = URLComponents(string: "\(APIConfig.baseURL)/\(endpoint)") else {
            throw APIError.invalidURL
        }

        if let queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.rawValue
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = authToken {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            urlRequest.httpBody = try encoder.encode(body)
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.noData
            }

            switch httpResponse.statusCode {
            case 200...299:
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                do {
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
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }

    /// Fire-and-forget variant for endpoints that return no meaningful body (e.g. DELETE 204).
    func requestVoid(
        endpoint: String,
        method: HTTPMethod = .get,
        body: (any Encodable)? = nil,
        queryItems: [URLQueryItem]? = nil
    ) async throws {
        guard var components = URLComponents(string: "\(APIConfig.baseURL)/\(endpoint)") else {
            throw APIError.invalidURL
        }

        if let queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.rawValue
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = authToken {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            urlRequest.httpBody = try encoder.encode(body)
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.noData
            }

            switch httpResponse.statusCode {
            case 200...299:
                return
            case 401:
                throw APIError.unauthorized
            default:
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw APIError.serverError(httpResponse.statusCode, message)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }

    // MARK: - Multipart Upload

    /// Uploads an image via multipart/form-data along with optional JSON-encodable fields.
    func upload<T: Decodable>(
        endpoint: String,
        imageData: Data,
        imageFieldName: String = "image",
        fileName: String = "artwork.jpg",
        mimeType: String = "image/jpeg",
        fields: [String: String] = [:]
    ) async throws -> T {
        guard let url = URL(string: "\(APIConfig.baseURL)/\(endpoint)") else {
            throw APIError.invalidURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = HTTPMethod.post.rawValue
        urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        if let token = authToken {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()

        // Append text fields
        for (key, value) in fields {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }

        // Append image data
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(imageFieldName)\"; filename=\"\(fileName)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(imageData)
        body.append("\r\n")

        // Close boundary
        body.append("--\(boundary)--\r\n")

        urlRequest.httpBody = body

        do {
            let (data, response) = try await session.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.noData
            }

            switch httpResponse.statusCode {
            case 200...299:
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                do {
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
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }
}

// MARK: - Data + Multipart Helpers

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}

// MARK: - API Response DTOs

struct APIUser: Codable, Identifiable {
    let id: String
    let username: String
    let displayName: String
    let walletAddress: String
    let bio: String?
    let balance: Double
    let avatarUrl: String?
}

struct APIArtwork: Codable, Identifiable {
    let id: String
    let title: String
    let artistName: String
    let description: String
    let imageUrl: String?
    let filePath: String?
    let price: Double
    let isForSale: Bool
    let styleId: String?
    let styleName: String?
    let blockchain: String
    let createdAt: String
}

struct APIAuction: Codable, Identifiable {
    let id: String
    let artworkId: String
    let startTime: String
    let endTime: String
    let currentBid: Double
    let startingPrice: Double
    let reservePrice: Double?
    let bidStep: Double
    let status: String
    let winnerId: String?
    let creatorId: String?
    let bidCount: Int
}

struct APIAuctionDetail: Codable {
    let auction: APIAuction
    let artwork: APIArtwork
    let bids: [APIBid]
}

struct APIBid: Codable, Identifiable {
    let id: String
    let auctionId: String
    let userId: String
    let userName: String
    let amount: Double
    let timestamp: String
}

struct APICollection: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let artworkIds: [String]
    let userId: String
    let isPrivate: Bool
    let isDefault: Bool
    let createdAt: String
    let updatedAt: String
}

struct APIArtStyle: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let iconName: String?
    let artworkCount: Int
}

struct APILoginResponse: Codable {
    let token: String
    let user: APIUser
}

struct APIUserStats: Codable {
    let ownedNFTs: Int
    let favorites: Int
    let collections: Int
    let auctionsWon: Int
}

struct APINotification: Codable, Identifiable {
    let id: String
    let type: String
    let title: String
    let message: String
    let isRead: Bool
    let createdAt: String
}

// MARK: - API Request DTOs

struct APILoginRequest: Codable {
    let walletAddress: String
    let password: String
}

struct APIRegisterRequest: Codable {
    let username: String
    let displayName: String
    let walletAddress: String
    let password: String
    let email: String?
}

struct APIPlaceBidRequest: Codable {
    let auctionId: String
    let amount: Double
}

struct APICreateArtworkRequest: Codable {
    let title: String
    let description: String?
    let styleId: String?
    let price: Double?
    let blockchain: String?
}

struct APICreateAuctionRequest: Codable {
    let artworkId: String
    let startingPrice: Double
    let reservePrice: Double?
    let bidStep: Double
    let durationHours: Int
}

struct APICreateCollectionRequest: Codable {
    let name: String
    let description: String?
    let isPrivate: Bool
}

// MARK: - API Endpoint Methods

extension NetworkService {

    // MARK: Auth

    func login(request body: APILoginRequest) async throws -> APILoginResponse {
        try await request(endpoint: "auth/login", method: .post, body: body)
    }

    func register(request body: APIRegisterRequest) async throws -> APILoginResponse {
        try await request(endpoint: "auth/register", method: .post, body: body)
    }

    // MARK: Artworks

    func fetchArtworks(styleId: String? = nil) async throws -> [APIArtwork] {
        var queryItems: [URLQueryItem]?
        if let styleId {
            queryItems = [URLQueryItem(name: "styleId", value: styleId)]
        }
        return try await request(endpoint: "artworks", queryItems: queryItems)
    }

    func fetchArtwork(id: String) async throws -> APIArtwork {
        try await request(endpoint: "artworks/\(id)")
    }

    func createArtwork(request body: APICreateArtworkRequest) async throws -> APIArtwork {
        try await request(endpoint: "artworks", method: .post, body: body)
    }

    func uploadArtworkImage(artworkId: String, imageData: Data) async throws -> APIArtwork {
        try await upload(
            endpoint: "artworks/\(artworkId)/upload-image",
            imageData: imageData,
            imageFieldName: "file",
            fileName: "artwork.jpg",
            mimeType: "image/jpeg"
        )
    }

    // MARK: Auctions

    func fetchAuctions(status: String? = nil) async throws -> [APIAuction] {
        var queryItems: [URLQueryItem]?
        if let status {
            queryItems = [URLQueryItem(name: "status", value: status)]
        }
        return try await request(endpoint: "auctions", queryItems: queryItems)
    }

    func fetchAuctionDetail(id: String) async throws -> APIAuctionDetail {
        try await request(endpoint: "auctions/\(id)/detail")
    }

    func createAuction(request body: APICreateAuctionRequest) async throws -> APIAuction {
        try await request(endpoint: "auctions", method: .post, body: body)
    }

    // MARK: Bids

    func placeBid(request body: APIPlaceBidRequest) async throws -> APIBid {
        try await request(endpoint: "bids", method: .post, body: body)
    }

    func fetchBids(auctionId: String) async throws -> [APIBid] {
        try await request(endpoint: "auctions/\(auctionId)/bids")
    }

    // MARK: User

    func fetchProfile() async throws -> APIUser {
        try await request(endpoint: "users/me")
    }

    func updateProfile(displayName: String?, bio: String?, avatarUrl: String?) async throws -> APIUser {
        struct UpdateProfileBody: Codable {
            let displayName: String?
            let bio: String?
            let avatarUrl: String?
        }
        return try await request(
            endpoint: "users/me",
            method: .put,
            body: UpdateProfileBody(displayName: displayName, bio: bio, avatarUrl: avatarUrl)
        )
    }

    func fetchStats() async throws -> APIUserStats {
        try await request(endpoint: "users/me/stats")
    }

    func fetchNotifications() async throws -> [APINotification] {
        try await request(endpoint: "users/me/notifications")
    }

    // MARK: Collections

    func fetchCollections() async throws -> [APICollection] {
        try await request(endpoint: "collections")
    }

    func createCollection(request body: APICreateCollectionRequest) async throws -> APICollection {
        try await request(endpoint: "collections", method: .post, body: body)
    }

    func addToCollection(collectionId: String, artworkId: String) async throws {
        struct Body: Codable { let artworkId: String }
        try await requestVoid(
            endpoint: "collections/\(collectionId)/artworks",
            method: .post,
            body: Body(artworkId: artworkId)
        )
    }

    func removeFromCollection(collectionId: String, artworkId: String) async throws {
        try await requestVoid(
            endpoint: "collections/\(collectionId)/artworks/\(artworkId)",
            method: .delete
        )
    }

    func deleteCollection(id: String) async throws {
        try await requestVoid(endpoint: "collections/\(id)", method: .delete)
    }

    // MARK: Styles

    func fetchStyles() async throws -> [APIArtStyle] {
        try await request(endpoint: "styles")
    }

    // MARK: NFT / Tokens

    func fetchMyTokens() async throws -> [APIArtwork] {
        try await request(endpoint: "nft/my-tokens")
    }

    func mintNFT(artworkId: String) async throws -> APIArtwork {
        struct Body: Codable { let artworkId: String }
        return try await request(endpoint: "nft/mint", method: .post, body: Body(artworkId: artworkId))
    }
}
