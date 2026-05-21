import SwiftUI

/// View for displaying another user's profile (navigated from bid list or artist name).
struct UserProfileView: View {
    let userId: UUID
    let userName: String
    let avatarUrl: String?

    @EnvironmentObject var auctionService: AuctionService
    @State private var profile: APIUserProfileDTO?
    @State private var isFollowing = false
    @State private var followersCount = 0
    @State private var followingCount = 0
    @State private var isLoadingFollow = false

    var body: some View {
        // ScrollView, а не List — SwiftUI List Sections активируют все NavigationLink-и
        // строки одним тапом, даже с .buttonStyle(.borderless). Эту проблему нельзя
        // починить локально, поэтому весь экран теперь через ScrollView.
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
            Group {
                VStack(spacing: 12) {
                    HStack(spacing: 16) {
                        AvatarView(
                            avatarUrl: profile?.avatarUrl ?? avatarUrl,
                            displayName: profile?.displayName ?? userName,
                            size: 60
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile?.displayName ?? userName)
                                .font(NFTTypography.headline)
                            if let username = profile?.username {
                                Text("@\(username)")
                                    .font(NFTTypography.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let bio = profile?.bio, !bio.isEmpty {
                                Text(bio)
                                    .font(NFTTypography.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                    }

                    // Stats row — каждая колонка кликабельная, ведёт на свой список.
                    // .buttonStyle(.borderless) — обязательно в List Section, иначе SwiftUI
                    // активирует ВСЕ кнопки строки одним тапом.
                    HStack(spacing: 0) {
                        NavigationLink {
                            UserListView(mode: .worksOf(userId: userId, name: profile?.displayName ?? userName))
                                .environmentObject(auctionService)
                        } label: {
                            statItem(value: profile?.artworksCount ?? 0, label: L10n.userArtworks)
                        }
                        .buttonStyle(.borderless)
                        Divider().frame(height: 30)
                        NavigationLink {
                            UserListView(mode: .followers(userId: userId))
                                .environmentObject(auctionService)
                        } label: {
                            statItem(value: followersCount, label: L10n.followers)
                        }
                        .buttonStyle(.borderless)
                        Divider().frame(height: 30)
                        NavigationLink {
                            UserListView(mode: .following(userId: userId))
                                .environmentObject(auctionService)
                        } label: {
                            statItem(value: followingCount, label: L10n.following)
                        }
                        .buttonStyle(.borderless)
                    }

                    // Action buttons.
                    // ВАЖНО: в SwiftUI List один тап по строке активирует ВСЕ Button-ы и
                    // NavigationLink-и внутри. .buttonStyle(.borderless) отключает это
                    // поведение и заставляет каждую кнопку реагировать только на свой тап.
                    HStack(spacing: 12) {
                        Button {
                            toggleFollow()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isFollowing ? "person.badge.minus" : "person.badge.plus")
                                Text(isFollowing ? L10n.unfollow : L10n.follow)
                            }
                            .font(NFTTypography.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(isFollowing ? .secondary : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(isFollowing ? Color(.tertiarySystemBackground) : Color.nftPurple)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.borderless)
                        .disabled(isLoadingFollow)

                        NavigationLink {
                            ChatView(userId: userId.uuidString, userName: profile?.displayName ?? userName, avatarUrl: profile?.avatarUrl ?? avatarUrl)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "bubble.left.fill")
                                Text(L10n.messages)
                            }
                            .font(NFTTypography.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.nftPurple)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.nftPurple.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.borderless)
                    }

                    // Шоурум юзера — открывает его работы в 3D-зале.
                    // Это и есть «шеринг шоурума»: кто угодно может зайти в чужой профиль
                    // и тапнуть кнопку — увидит работы этого юзера в выбранной теме.
                    let userArtworks = auctionService.auctions.filter { $0.creatorId == userId }.map { $0.artwork }
                    if !userArtworks.isEmpty {
                        NavigationLink {
                            ShowroomView(
                                artworks: userArtworks,
                                collectionName: profile?.displayName ?? userName,
                                collectionId: nil
                            )
                            .environmentObject(auctionService)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "cube.transparent")
                                Text(L10n.showroom)
                            }
                            .font(NFTTypography.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(LinearGradient.nftPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.borderless)
                        .padding(.top, 4)
                    }
                }
                .padding(.vertical, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            sectionDivider

            // User's artworks (created)
            sectionHeader(L10n.userArtworks)
            let userArtworks = auctionService.auctions.filter { $0.creatorId == userId }
            if userArtworks.isEmpty {
                emptyHint
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(userArtworks) { auction in
                        NavigationLink {
                            ArtworkDetailView(auction: auction).environmentObject(auctionService)
                        } label: {
                            artworkRow(auction: auction, subtitle: auction.formattedCurrentBid, subtitleColor: .nftPurple)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }

            sectionDivider

            // Auction activity (bids placed by this user)
            sectionHeader(L10n.auctionActivity)
            let bidAuctions = auctionService.auctions.filter { auction in
                auction.bids.contains { $0.userId == userId }
            }
            if bidAuctions.isEmpty {
                emptyHint
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(bidAuctions) { auction in
                        let userBids = auction.bids.filter { $0.userId == userId }
                        let highestBid = userBids.max(by: { $0.amount < $1.amount })
                        let subtitle = highestBid.map { L10n.bidsCount(userBids.count) + " — " + $0.formattedAmount } ?? ""
                        NavigationLink {
                            ArtworkDetailView(auction: auction).environmentObject(auctionService)
                        } label: {
                            artworkRow(auction: auction, subtitle: subtitle, subtitleColor: .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }

            Spacer(minLength: 24)
            } // VStack
        }
        .navigationTitle(profile?.displayName ?? userName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadProfile() }
    }

    private var sectionDivider: some View {
        Divider().padding(.horizontal, 16)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(NFTTypography.headline)
            .padding(.horizontal, 16)
            .padding(.top, 4)
    }

    private var emptyHint: some View {
        Text(L10n.noRecentActivity)
            .font(NFTTypography.body)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
    }

    private func artworkRow(auction: Auction, subtitle: String, subtitleColor: Color) -> some View {
        HStack(spacing: 12) {
            ArtworkImageView(artwork: auction.artwork)
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(auction.artwork.title)
                    .font(NFTTypography.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(NFTTypography.caption)
                    .foregroundStyle(subtitleColor)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
    }

    private func statItem(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(NFTTypography.headline)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func loadProfile() async {
        do {
            let p = try await NetworkService.shared.fetchUserProfile(userId: userId.uuidString)
            await MainActor.run {
                profile = p
                isFollowing = p.isFollowedByMe
                followersCount = p.followersCount
                followingCount = p.followingCount
            }
        } catch {}
        MetricsService.shared.trackFeatureUsage("user_profile")
    }

    private func toggleFollow() {
        isLoadingFollow = true
        Task {
            do {
                let status = try await NetworkService.shared.toggleFollow(userId: userId.uuidString)
                await MainActor.run {
                    isFollowing = status.isFollowedByMe
                    followersCount = status.followersCount
                    followingCount = status.followingCount
                    isLoadingFollow = false
                }
            } catch {
                await MainActor.run { isLoadingFollow = false }
            }
        }
    }
}
