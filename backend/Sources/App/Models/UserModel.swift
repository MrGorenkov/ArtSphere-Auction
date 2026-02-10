import Vapor
import Fluent

final class UserModel: Model, Content, @unchecked Sendable {
    static let schema = "users"

    @ID(key: .id) var id: UUID?
    @Field(key: "username") var username: String
    @Field(key: "display_name") var displayName: String
    @OptionalField(key: "email") var email: String?
    @Field(key: "wallet_address") var walletAddress: String
    @OptionalField(key: "card_number") var cardNumber: String?
    @Field(key: "bio") var bio: String
    @OptionalField(key: "avatar_url") var avatarUrl: String?
    @Field(key: "balance") var balance: Double
    @Field(key: "password_hash") var passwordHash: String
    @Field(key: "is_active") var isActive: Bool
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

    // Relationships
    @Children(for: \.$creator) var artworks: [ArtworkModel]
    @Children(for: \.$user) var collections: [CollectionModel]

    init() {}

    init(
        id: UUID? = nil,
        username: String,
        displayName: String,
        email: String? = nil,
        walletAddress: String,
        cardNumber: String? = nil,
        bio: String = "",
        balance: Double = 10.0,
        passwordHash: String
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.email = email
        self.walletAddress = walletAddress
        self.cardNumber = cardNumber
        self.bio = bio
        self.balance = balance
        self.passwordHash = passwordHash
        self.isActive = true
    }
}

extension UserModel {
    func toDTO() -> UserDTO {
        UserDTO(
            id: self.id?.uuidString ?? "",
            username: self.username,
            displayName: self.displayName,
            walletAddress: self.walletAddress,
            bio: self.bio,
            balance: self.balance,
            avatarUrl: self.avatarUrl
        )
    }
}
