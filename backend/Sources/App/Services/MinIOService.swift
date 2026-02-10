import Vapor
import Foundation

/// S3-совместимый клиент для MinIO — загрузка/скачивание файлов
struct MinIOService {
    let endpoint: String
    let accessKey: String
    let secretKey: String
    let publicUrl: String

    // Бакеты
    static let artworksBucket = "artworks"
    static let modelsBucket = "3d-models"
    static let avatarsBucket = "avatars"
    static let filesBucket = "files"

    init(app: Application) {
        self.endpoint = Environment.get("MINIO_ENDPOINT") ?? "http://localhost:9000"
        self.accessKey = Environment.get("MINIO_ACCESS_KEY") ?? "nftarts_minio"
        self.secretKey = Environment.get("MINIO_SECRET_KEY") ?? "minio_secret_key"
        self.publicUrl = Environment.get("MINIO_PUBLIC_URL") ?? "http://localhost:9000"
    }

    /// Загрузить файл в MinIO
    func upload(
        data: ByteBuffer,
        bucket: String,
        key: String,
        contentType: String,
        on client: Client
    ) async throws -> String {
        let url = "\(endpoint)/\(bucket)/\(key)"

        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: contentType)

        let response = try await client.put(URI(string: url), headers: headers) { req in
            req.body = data
        }

        guard response.status == .ok || response.status == .created else {
            throw Abort(.internalServerError, reason: "MinIO upload failed: \(response.status)")
        }

        return "\(publicUrl)/\(bucket)/\(key)"
    }

    /// Получить публичный URL файла
    func publicURL(bucket: String, key: String) -> String {
        return "\(publicUrl)/\(bucket)/\(key)"
    }

    /// Удалить файл из MinIO
    func delete(
        bucket: String,
        key: String,
        on client: Client
    ) async throws {
        let url = "\(endpoint)/\(bucket)/\(key)"

        let response = try await client.delete(URI(string: url))

        guard response.status == .noContent || response.status == .ok else {
            throw Abort(.internalServerError, reason: "MinIO delete failed: \(response.status)")
        }
    }
}

// MARK: - Application Extension

extension Application {
    var minio: MinIOService {
        MinIOService(app: self)
    }
}

extension Request {
    var minio: MinIOService {
        MinIOService(app: self.application)
    }
}
