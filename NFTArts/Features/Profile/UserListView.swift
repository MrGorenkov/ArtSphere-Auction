import SwiftUI

/// Универсальный список юзеров — используется для followers/following.
/// Тапы по строкам открывают `UserProfileView` соответствующего юзера.
struct UserListView: View {
    enum Mode {
        case followers(userId: UUID)
        case following(userId: UUID)
        case worksOf(userId: UUID, name: String) // показывает работы юзера через ауцион-сервис

        var title: String {
            switch self {
            case .followers:    return L10n.followers
            case .following:    return L10n.following
            case .worksOf(_, _): return L10n.userArtworks
            }
        }
    }

    let mode: Mode
    @EnvironmentObject var auctionService: AuctionService
    @State private var users: [APIUser] = []
    @State private var isLoading: Bool = true
    @State private var loadError: String?

    var body: some View {
        Group {
            switch mode {
            case .followers, .following:
                userList
            case .worksOf(let userId, _):
                worksList(userId: userId)
            }
        }
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: - Followers / following list

    @ViewBuilder
    private var userList: some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = loadError {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                Text(err).font(NFTTypography.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if users.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "person.2.slash")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text(L10n.noRecentActivity).font(NFTTypography.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(users, id: \.id) { user in
                NavigationLink {
                    UserProfileView(
                        userId: UUID(uuidString: user.id) ?? UUID(),
                        userName: user.displayName,
                        avatarUrl: user.avatarUrl
                    )
                    .environmentObject(auctionService)
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(avatarUrl: user.avatarUrl, displayName: user.displayName, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayName).font(NFTTypography.subheadline).fontWeight(.medium)
                            Text("@\(user.username)").font(NFTTypography.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Works list (через auctionService)

    private func worksList(userId: UUID) -> some View {
        let works = auctionService.auctions.filter { $0.creatorId == userId }
        return Group {
            if works.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text(L10n.noRecentActivity).font(NFTTypography.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(works) { auction in
                    NavigationLink {
                        ArtworkDetailView(auction: auction).environmentObject(auctionService)
                    } label: {
                        HStack(spacing: 12) {
                            ArtworkImageView(artwork: auction.artwork)
                                .frame(width: 50, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(auction.artwork.title).font(NFTTypography.subheadline).fontWeight(.medium)
                                Text(auction.formattedCurrentBid).font(NFTTypography.caption).foregroundStyle(.nftPurple)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            switch mode {
            case .followers(let uid):
                users = try await NetworkService.shared.fetchFollowers(of: uid.uuidString)
            case .following(let uid):
                users = try await NetworkService.shared.fetchFollowing(of: uid.uuidString)
            case .worksOf:
                break // данные берутся из auctionService локально
            }
        } catch {
            loadError = error.localizedDescription
        }
    }
}
