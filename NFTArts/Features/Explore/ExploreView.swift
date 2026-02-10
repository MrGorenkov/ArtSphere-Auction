import SwiftUI

struct ExploreView: View {
    @EnvironmentObject var auctionService: AuctionService
    @EnvironmentObject var lang: LanguageManager
    @State private var searchText = ""

    private var categories: [NFTArtwork.ArtworkCategory] {
        NFTArtwork.ArtworkCategory.allCases
    }

    private var filteredAuctions: [Auction] {
        if searchText.isEmpty {
            return auctionService.auctions
        }
        return auctionService.auctions.filter {
            $0.artwork.title.localizedCaseInsensitiveContains(searchText) ||
            $0.artwork.artistName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if searchText.isEmpty {
                        categoriesSection
                        trendingSection
                        recentBidsSection
                    } else {
                        searchResults
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(L10n.exploreTitle)
            .searchable(text: $searchText, prompt: L10n.searchArtistsArtworks)
        }
    }

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.categories)
                .font(NFTTypography.title2)
                .padding(.horizontal)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(categories) { category in
                    NavigationLink {
                        CategoryDetailView(
                            category: category,
                            auctions: auctionService.auctions.filter { $0.artwork.category == category }
                        )
                    } label: {
                        CategoryCard(
                            category: category,
                            count: auctionService.auctions.filter { $0.artwork.category == category }.count
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private var trendingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.trending)
                .font(NFTTypography.title2)
                .padding(.horizontal)

            ForEach(auctionService.auctions.sorted(by: { $0.bidCount > $1.bidCount }).prefix(5)) { auction in
                NavigationLink {
                    ArtworkDetailView(auction: auction)
                } label: {
                    TrendingRow(auction: auction)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
        }
    }

    private var recentBidsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.recentActivity)
                .font(NFTTypography.title2)
                .padding(.horizontal)

            ForEach(auctionService.notifications.prefix(5)) { notification in
                HStack(spacing: 12) {
                    Image(systemName: notification.iconName)
                        .font(.system(size: 16))
                        .foregroundStyle(notificationColor(notification))
                        .frame(width: 32, height: 32)
                        .background(notificationColor(notification).opacity(0.1))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(notification.title)
                            .font(NFTTypography.caption)
                            .fontWeight(.semibold)
                        Text(notification.message)
                            .font(NFTTypography.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(notification.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(NFTTypography.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }
        }
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.resultsCount(filteredAuctions.count))
                .font(NFTTypography.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            ForEach(filteredAuctions) { auction in
                NavigationLink {
                    ArtworkDetailView(auction: auction)
                } label: {
                    TrendingRow(auction: auction)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
        }
    }

    private func notificationColor(_ n: AuctionNotification) -> Color {
        switch n.type {
        case .newBid: return .nftBlue
        case .bidPlaced: return .nftPurple
        case .auctionWon: return .nftOrange
        case .auctionEnded: return .gray
        case .nftCreated: return .nftGreen
        }
    }
}

// MARK: - Category Card

struct CategoryCard: View {
    let category: NFTArtwork.ArtworkCategory
    var count: Int = 0

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: category.iconName)
                .font(.system(size: 28))
                .foregroundStyle(.nftPurple)

            Text(L10n.categoryName(category))
                .font(NFTTypography.caption)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)

            Text("\(count)")
                .font(NFTTypography.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .nftCardStyle()
    }
}

// MARK: - Category Detail View

struct CategoryDetailView: View {
    let category: NFTArtwork.ArtworkCategory
    let auctions: [Auction]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(auctions) { auction in
                    NavigationLink {
                        ArtworkDetailView(auction: auction)
                    } label: {
                        AuctionCardView(auction: auction)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationTitle(L10n.categoryName(category))
    }
}

// MARK: - Trending Row

struct TrendingRow: View {
    let auction: Auction

    var body: some View {
        HStack(spacing: 12) {
            ArtworkImageView(artwork: auction.artwork)
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(auction.artwork.title)
                    .font(NFTTypography.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(auction.artwork.artistName)
                        .font(NFTTypography.caption)
                        .foregroundStyle(.secondary)
                    if auction.isActive {
                        Circle()
                            .fill(.nftGreen)
                            .frame(width: 6, height: 6)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(auction.formattedCurrentBid)
                    .font(NFTTypography.bid)
                    .foregroundStyle(.nftPurple)
                Text(L10n.bidsCount(auction.bidCount))
                    .font(NFTTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .nftCardStyle()
    }
}
