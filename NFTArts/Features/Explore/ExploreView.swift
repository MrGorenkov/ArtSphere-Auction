import SwiftUI

struct ExploreView: View {
    @EnvironmentObject var auctionService: AuctionService
    @EnvironmentObject var lang: LanguageManager
    @State private var searchText = ""
    @State private var sortMode: SortMode = .recent
    @State private var statusFilter: StatusFilter = .all

    enum SortMode: CaseIterable, Identifiable {
        case recent, highestBid, mostBids, endingSoon
        var id: Self { self }
        var label: String {
            switch self {
            case .recent:      return L10n.sortRecent
            case .highestBid:  return L10n.sortHighestBid
            case .mostBids:    return L10n.sortMostBids
            case .endingSoon:  return L10n.sortEndingSoon
            }
        }
        var icon: String {
            switch self {
            case .recent:      return "clock"
            case .highestBid:  return "arrow.up.circle"
            case .mostBids:    return "flame"
            case .endingSoon:  return "hourglass"
            }
        }
    }

    enum StatusFilter: CaseIterable, Identifiable {
        case all, active, upcoming, sold
        var id: Self { self }
        var label: String {
            switch self {
            case .all:      return L10n.filterAll
            case .active:   return L10n.active
            case .upcoming: return L10n.upcoming
            case .sold:     return L10n.sold
            }
        }
        func matches(_ auction: Auction) -> Bool {
            switch self {
            case .all:      return true
            case .active:   return auction.status == .active
            case .upcoming: return auction.status == .upcoming
            case .sold:     return auction.status == .sold
            }
        }
    }

    private var categories: [NFTArtwork.ArtworkCategory] {
        NFTArtwork.ArtworkCategory.allCases
    }

    private var filteredAuctions: [Auction] {
        var result = auctionService.auctions.filter { statusFilter.matches($0) }
        if !searchText.isEmpty {
            result = result.filter {
                $0.artwork.title.localizedCaseInsensitiveContains(searchText) ||
                $0.artwork.artistName.localizedCaseInsensitiveContains(searchText)
            }
        }
        switch sortMode {
        case .recent:
            result.sort { $0.startTime > $1.startTime }
        case .highestBid:
            result.sort { $0.currentBid > $1.currentBid }
        case .mostBids:
            result.sort { $0.bidCount > $1.bidCount }
        case .endingSoon:
            result.sort { $0.timeRemaining < $1.timeRemaining }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if searchText.isEmpty && statusFilter == .all && sortMode == .recent {
                        categoriesSection
                        trendingSection
                        recentBidsSection
                    } else {
                        activeFiltersChips
                        searchResults
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(L10n.exploreTitle)
            .searchable(text: $searchText, prompt: L10n.searchArtistsArtworks)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    sortFilterMenu
                }
            }
        }
    }

    private var sortFilterMenu: some View {
        Menu {
            Picker(L10n.sortBy, selection: $sortMode) {
                ForEach(SortMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.icon).tag(mode)
                }
            }
            Picker(L10n.filterStatus, selection: $statusFilter) {
                ForEach(StatusFilter.allCases) { f in
                    Text(f.label).tag(f)
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 18, weight: .semibold))
        }
    }

    @ViewBuilder
    private var activeFiltersChips: some View {
        let chips: [String] = [
            statusFilter == .all ? nil : "\(L10n.filterStatus): \(statusFilter.label)",
            sortMode == .recent ? nil : "\(L10n.sortBy): \(sortMode.label)"
        ].compactMap { $0 }

        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chips, id: \.self) { chip in
                        Text(chip)
                            .font(NFTTypography.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.nftPurple.opacity(0.15))
                            .foregroundStyle(.nftPurple)
                            .clipShape(Capsule())
                    }
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            statusFilter = .all
                            sortMode = .recent
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
            }
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
