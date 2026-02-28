import Vapor
import Foundation
import Crypto

/// S3-совместимый клиент для MinIO / Cloudflare R2
/// Локально: простой PUT (MinIO с публичными бакетами)
/// Продакшн: подписанные запросы AWS Signature V4 (Cloudflare R2)
struct MinIOService {
    let endpoint: String        // внутренний endpoint для upload (PUT)
    let publicUrl: String       // публичный URL для отдачи файлов
    let accessKey: String
    let secretKey: String
    let region: String
    let useSignedRequests: Bool  // true когда задан AWS_ACCESS_KEY_ID

    static let artworksBucket = "artworks"
    static let modelsBucket = "3d-models"
    static let avatarsBucket = "avatars"
    static let filesBucket = "files"

    // Имя основного бакета (для R2 — один бакет, "bucket" параметры становятся папками)
    let mainBucket: String

    init(app: Application) {
        // Cloudflare R2 / AWS S3 mode — используется когда задан AWS_ACCESS_KEY_ID
        if let awsKey = Environment.get("AWS_ACCESS_KEY_ID") {
            self.accessKey = awsKey
            self.secretKey = Environment.get("AWS_SECRET_ACCESS_KEY") ?? ""
            self.region = Environment.get("AWS_REGION") ?? "auto"
            self.endpoint = Environment.get("S3_ENDPOINT") ?? ""
            self.publicUrl = Environment.get("S3_PUBLIC_URL") ?? self.endpoint
            self.mainBucket = Environment.get("S3_BUCKET") ?? "nftarts"
            self.useSignedRequests = true
        } else {
            // Локальный MinIO (простые неподписанные PUT, отдельные бакеты)
            self.endpoint = Environment.get("MINIO_ENDPOINT") ?? "http://localhost:9000"
            self.accessKey = Environment.get("MINIO_ACCESS_KEY") ?? "nftarts_minio"
            self.secretKey = Environment.get("MINIO_SECRET_KEY") ?? "minio_secret_key"
            self.region = "us-east-1"
            self.publicUrl = Environment.get("MINIO_PUBLIC_URL") ?? "http://localhost:9000"
            self.mainBucket = ""  // MinIO: бакет прямо в URL
            self.useSignedRequests = false
        }
    }

    // MARK: - Upload

    func upload(
        data: ByteBuffer,
        bucket: String,
        key: String,
        contentType: String,
        on client: Client
    ) async throws -> String {
        let bodyData = Data(buffer: data)
        // R2: один бакет + папка; MinIO: отдельные бакеты
        let s3Path = mainBucket.isEmpty ? "/\(bucket)/\(key)" : "/\(mainBucket)/\(bucket)/\(key)"
        let urlString = mainBucket.isEmpty ? "\(endpoint)/\(bucket)/\(key)" : "\(endpoint)\(s3Path)"
        guard let url = URL(string: urlString) else {
            throw Abort(.internalServerError, reason: "Invalid S3 URL: \(urlString)")
        }

        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: contentType)

        if useSignedRequests {
            let host = url.host ?? ""
            let signer = AWSV4Signer(accessKey: accessKey, secretKey: secretKey, region: region)
            let signedHeaders = signer.signedHeaders(
                method: "PUT",
                path: s3Path,
                body: bodyData,
                contentType: contentType,
                host: host
            )
            for (name, value) in signedHeaders {
                headers.replaceOrAdd(name: .init(name), value: value)
            }
        }

        let response = try await client.put(URI(string: urlString), headers: headers) { req in
            req.body = ByteBuffer(data: bodyData)
        }

        guard response.status == .ok || response.status == .created || response.status == .noContent else {
            throw Abort(.internalServerError, reason: "S3 upload failed (\(response.status)): \(response.body.map { String(buffer: $0) } ?? "")")
        }

        return "\(publicUrl)/\(bucket)/\(key)"
    }

    func publicURL(bucket: String, key: String) -> String {
        // R2 r2.dev URL уже включает бакет как корень — просто folder/key
        "\(publicUrl)/\(bucket)/\(key)"
    }

    func delete(bucket: String, key: String, on client: Client) async throws {
        let s3Path = mainBucket.isEmpty ? "/\(bucket)/\(key)" : "/\(mainBucket)/\(bucket)/\(key)"
        let urlString = mainBucket.isEmpty ? "\(endpoint)/\(bucket)/\(key)" : "\(endpoint)\(s3Path)"
        guard let url = URL(string: urlString) else { return }

        var headers = HTTPHeaders()

        if useSignedRequests {
            let host = url.host ?? ""
            let signer = AWSV4Signer(accessKey: accessKey, secretKey: secretKey, region: region)
            let signedHeaders = signer.signedHeaders(
                method: "DELETE",
                path: s3Path,
                body: Data(),
                contentType: "application/octet-stream",
                host: host
            )
            for (name, value) in signedHeaders {
                headers.replaceOrAdd(name: .init(name), value: value)
            }
        }

        let response = try await client.delete(URI(string: urlString), headers: headers)
        guard response.status == .noContent || response.status == .ok else {
            throw Abort(.internalServerError, reason: "S3 delete failed: \(response.status)")
        }
    }
}

// MARK: - AWS Signature V4

private struct AWSV4Signer {
    let accessKey: String
    let secretKey: String
    let region: String

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f
    }()

    func signedHeaders(
        method: String,
        path: String,
        body: Data,
        contentType: String,
        host: String,
        date: Date = Date()
    ) -> [(String, String)] {
        let amzDate = Self.dateTimeFormatter.string(from: date)
        let shortDate = String(amzDate.prefix(8))

        let payloadHash = sha256Hex(body)
        let canonicalHeaders =
            "content-type:\(contentType)\n" +
            "host:\(host)\n" +
            "x-amz-content-sha256:\(payloadHash)\n" +
            "x-amz-date:\(amzDate)\n"
        let signedHeadersList = "content-type;host;x-amz-content-sha256;x-amz-date"

        let canonicalRequest = [method, path, "", canonicalHeaders, signedHeadersList, payloadHash]
            .joined(separator: "\n")
        let canonicalRequestHash = sha256Hex(Data(canonicalRequest.utf8))

        let credentialScope = "\(shortDate)/\(region)/s3/aws4_request"
        let stringToSign = "AWS4-HMAC-SHA256\n\(amzDate)\n\(credentialScope)\n\(canonicalRequestHash)"

        let kSecret  = SymmetricKey(data: Data("AWS4\(secretKey)".utf8))
        let kDate    = hmacSHA256(key: kSecret, data: shortDate)
        let kRegion  = hmacSHA256(key: kDate, data: region)
        let kService = hmacSHA256(key: kRegion, data: "s3")
        let kSigning = hmacSHA256(key: kService, data: "aws4_request")

        let signatureBytes = HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: kSigning)
        let signature = Data(signatureBytes).map { String(format: "%02x", $0) }.joined()

        let authorization = "AWS4-HMAC-SHA256 Credential=\(accessKey)/\(credentialScope), SignedHeaders=\(signedHeadersList), Signature=\(signature)"

        return [
            ("Authorization", authorization),
            ("x-amz-date", amzDate),
            ("x-amz-content-sha256", payloadHash),
            ("Content-Type", contentType)
        ]
    }

    private func sha256Hex(_ data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func hmacSHA256(key: SymmetricKey, data: String) -> SymmetricKey {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(data.utf8), using: key)
        return SymmetricKey(data: Data(mac))
    }
}

// MARK: - Application Extensions

extension Application {
    var minio: MinIOService { MinIOService(app: self) }
}

extension Request {
    var minio: MinIOService { MinIOService(app: self.application) }
}
