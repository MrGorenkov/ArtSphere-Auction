import SwiftUI

struct FeedView: View {
    @StateObject private var viewModel = FeedViewModel()
    @EnvironmentObject var auctionService: AuctionService
    @EnvironmentObject var lang: LanguageManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Notifications banner
                    notificationBanner

                    // Category filter
                    categoryFilter
                        .padding(.top, 8)

                    // Featured carousel
                    if viewModel.selectedCategory == nil && viewModel.searchText.isEmpty {
                        featuredSection
                    }

                    // Auction grid
                    auctionGrid
                }
            }
            .navigationTitle(L10n.feedTitle)
            .searchable(text: $viewModel.searchText, prompt: L10n.searchArtworks)
            .onAppear {
                viewModel.bind(to: auctionService)
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                }
            }
        }
    }

    // MARK: - Notification Banner

    @ViewBuilder
    private var notificationBanner: some View {
        if let latestWin = auctionService.wonAuctions.last {
            HStack(spacing: 12) {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(.yellow)
                    .font(.system(size: 20))

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.auctionWon)
                        .font(NFTTypography.subheadline)
                        .fontWeight(.semibold)
                    Text("\(L10n.youWon) \"\(latestWin.artwork.title)\"")
                        .font(NFTTypography.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    ArtworkDetailView(auction: latestWin)
                } label: {
                    Text(L10n.view)
                        .font(NFTTypography.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.nftPurple)
                        .clipShape(Capsule())
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    // MARK: - Category Filter

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(NFTArtwork.ArtworkCategory.allCases) { category in
                    CategoryChip(
                        title: L10n.categoryName(category),
                        icon: category.iconName,
                        isSelected: viewModel.selectedCategory == category
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            viewModel.selectCategory(category)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Featured Section

    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.featured)
                .font(NFTTypography.title2)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(auctionService.featuredAuctions) { auction in
                        NavigationLink(value: auction) {
                            FeaturedAuctionCard(auction: auction)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
        .navigationDestination(for: Auction.self) { auction in
            ArtworkDetailView(auction: auction)
        }
    }

    // MARK: - Auction Grid

    private var auctionGrid: some View {
        LazyVStack(spacing: 16) {
            ForEach(viewModel.filteredAuctions) { auction in
                NavigationLink(value: auction) {
                    AuctionCardView(auction: auction)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .navigationDestination(for: Auction.self) { auction in
            ArtworkDetailView(auction: auction)
        }
    }
}

// MARK: - Category Chip

struct CategoryChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(NFTTypography.caption)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Color.nftPurple : Color(.tertiarySystemBackground))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
    }
}

// MARK: - Featured Auction Card

struct FeaturedAuctionCard: View {
    let auction: Auction

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ArtworkImageView(artwork: auction.artwork)
                .frame(width: 280, height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(auction.artwork.title)
                    .font(NFTTypography.headline)
                    .foregroundStyle(.white)

                Text(auction.artwork.artistName)
                    .font(NFTTypography.subheadline)
                    .foregroundStyle(.white.opacity(0.8))

                HStack {
                    Text(auction.formattedCurrentBid)
                        .font(NFTTypography.bid)
                        .foregroundStyle(.white)

                    Spacer()

                    CountdownTimerView(endTime: auction.endTime, compact: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
        }
        .shadow(color: .black.opacity(0.2), radius: 15, x: 0, y: 8)
    }
}
