import SwiftUI

struct AuctionsListView: View {
    @State private var auctions: [AdminAuction] = []
    @State private var isLoading = true
    @State private var statusFilter: String? = nil
    @State private var selectedAuction: AdminAuction?
    @State private var bids: [AdminBid] = []
    @State private var isLoadingBids = false

    private var filteredAuctions: [AdminAuction] {
        guard let filter = statusFilter else { return auctions }
        return auctions.filter { $0.status == filter }
    }

    private var statusDistribution: [String: Int] {
        var dist: [String: Int] = [:]
        for a in auctions {
            dist[a.status, default: 0] += 1
        }
        return dist
    }

    var body: some View {
        HSplitView {
            // Auctions list
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Аукционы")
                        .font(.title2)
                        .fontWeight(.bold)

                    Spacer()

                    Picker("Статус", selection: $statusFilter) {
                        Text("Все").tag(nil as String?)
                        Text("Active").tag("active" as String?)
                        Text("Ended").tag("ended" as String?)
                        Text("Sold").tag("sold" as String?)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 320)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

                // Status chart
                if !statusDistribution.isEmpty {
                    StatusBar(statuses: statusDistribution)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }

                Divider()

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredAuctions, selection: $selectedAuction) { auction in
                        AuctionRow(auction: auction)
                            .tag(auction)
                            .contextMenu {
                                if auction.status == "active" || auction.status == "upcoming" {
                                    Button("Отменить аукцион") {
                                        cancelAuction(auction)
                                    }
                                }
                            }
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                    .onChange(of: selectedAuction) { newVal in
                        if let a = newVal {
                            loadBids(auctionId: a.id)
                        }
                    }
                }
            }
            .frame(minWidth: 550)

            // Detail panel
            if let auction = selectedAuction {
                AuctionDetailView(auction: auction, bids: bids, isLoadingBids: isLoadingBids) {
                    cancelAuction(auction)
                }
                .frame(minWidth: 320, maxWidth: 420)
            } else {
                VStack {
                    Image(systemName: "hammer")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Выберите аукцион")
                        .foregroundColor(.secondary)
                }
                .frame(minWidth: 320, maxWidth: 420, maxHeight: .infinity)
            }
        }
        .task { await loadData() }
    }

    private func loadData() async {
        isLoading = true
        do {
            auctions = try await AdminNetworkService.shared.fetchAuctions()
        } catch {}
        isLoading = false
    }

    private func loadBids(auctionId: String) {
        isLoadingBids = true
        Task {
            do {
                bids = try await AdminNetworkService.shared.fetchAuctionBids(auctionId: auctionId)
            } catch {
                bids = []
            }
            isLoadingBids = false
        }
    }

    private func cancelAuction(_ auction: AdminAuction) {
        Task {
            do {
                let updated = try await AdminNetworkService.shared.cancelAuction(id: auction.id)
                if let idx = auctions.firstIndex(where: { $0.id == auction.id }) {
                    auctions[idx] = updated
                }
                if selectedAuction?.id == auction.id { selectedAuction = updated }
            } catch {}
        }
    }
}

struct AuctionRow: View {
    let auction: AdminAuction

    var body: some View {
        HStack(spacing: 12) {
            // Artwork thumbnail
            AsyncImage(url: auction.artworkImageUrl.flatMap { URL(string: $0) }) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.purple.opacity(0.15))
                    .overlay(Image(systemName: "hammer").foregroundColor(.purple.opacity(0.5)))
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(auction.artworkTitle)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let creator = auction.creatorName {
                        Text(creator)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text("·")
                        .foregroundColor(.secondary)
                    Text("\(auction.bidCount) ставок")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.2f ETH", auction.currentBid > 0 ? auction.currentBid : auction.startingPrice))
                    .font(.subheadline)
                    .fontWeight(.medium)

                StatusBadge(status: auction.status)
            }
        }
        .padding(.vertical, 4)
    }
}

extension AdminAuction: Hashable {
    static func == (lhs: AdminAuction, rhs: AdminAuction) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
