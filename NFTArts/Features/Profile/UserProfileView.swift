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
        List {
            // Profile header
            Section {
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

                    // Stats row
                    HStack(spacing: 0) {
                        statItem(value: profile?.artworksCount ?? 0, label: L10n.userArtworks)
                        Divider().frame(height: 30)
                        statItem(value: followersCount, label: L10n.followers)
                        Divider().frame(height: 30)
                        statItem(value: followingCount, label: L10n.following)
                    }

                    // Action buttons
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
                    }
                }
                .padding(.vertical, 4)
            }

            // User's artworks (created)
            Section(L10n.userArtworks) {
                let userArtworks = auctionService.auctions.filter { $0.creatorId == userId }
                if userArtworks.isEmpty {
                    Text(L10n.noRecentActivity)
                        .font(NFTTypography.body)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(userArtworks) { auction in
                        NavigationLink(destination: ArtworkDetailView(auction: auction)) {
                            HStack(spacing: 12) {
                                ArtworkImageView(artwork: auction.artwork)
                                    .frame(width: 50, height: 50)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(auction.artwork.title)
                                        .font(NFTTypography.subheadline)
                                        .fontWeight(.medium)
                                    Text(auction.formattedCurrentBid)
                                        .font(NFTTypography.caption)
                                        .foregroundStyle(.nftPurple)
                                }
                            }
                        }
                    }
                }
            }

            // Auction activity (bids placed by this user)
            Section(L10n.auctionActivity) {
                let bidAuctions = auctionService.auctions.filter { auction in
                    auction.bids.contains { $0.userId == userId }
                }
                if bidAuctions.isEmpty {
                    Text(L10n.noRecentActivity)
                        .font(NFTTypography.body)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(bidAuctions) { auction in
                        let userBids = auction.bids.filter { $0.userId == userId }
                        let highestBid = userBids.max(by: { $0.amount < $1.amount })

                        NavigationLink(destination: ArtworkDetailView(auction: auction)) {
                            HStack(spacing: 12) {
                                ArtworkImageView(artwork: auction.artwork)
                                    .frame(width: 50, height: 50)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(auction.artwork.title)
                                        .font(NFTTypography.subheadline)
                                        .fontWeight(.medium)
                                    if let bid = highestBid {
                                        Text(L10n.bidsCount(userBids.count) + " — " + bid.formattedAmount)
                                            .font(NFTTypography.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(profile?.displayName ?? userName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadProfile() }
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
