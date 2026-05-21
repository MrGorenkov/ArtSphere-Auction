import SwiftUI

struct AuctionHistoryView: View {
    @EnvironmentObject var auctionService: AuctionService
    @EnvironmentObject var lang: LanguageManager

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if auctionService.completedAuctions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.badge.checkmark.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text(L10n.noCompletedAuctions)
                            .font(NFTTypography.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 60)
                } else {
                    ForEach(auctionService.completedAuctions) { auction in
                        NavigationLink(destination: ArtworkDetailView(auction: auction).environmentObject(auctionService)) {
                            completedAuctionCard(auction)
                        }
                        .tint(.primary)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(L10n.auctionHistory)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            auctionService.fetchCompletedAuctions()
        }
        .refreshable {
            auctionService.fetchCompletedAuctions()
        }
    }

    private func completedAuctionCard(_ auction: Auction) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ArtworkImageView(artwork: auction.artwork)
                    .frame(width: 70, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(auction.artwork.title)
                        .font(NFTTypography.headline)
                        .lineLimit(1)
                    Text(auction.artwork.artistName)
                        .font(NFTTypography.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        Image(systemName: auction.status == .sold ? "trophy.fill" : "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(auction.status == .sold ? .yellow : .gray)
                        Text(auction.status == .sold ? L10n.sold : L10n.ended)
                            .font(NFTTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(auction.formattedCurrentBid)
                        .font(NFTTypography.bid)
                        .foregroundStyle(.nftPurple)
                    Text(L10n.bidsCount(auction.bidCount))
                        .font(NFTTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Protocol info
            if let winner = auction.highestBid {
                HStack(spacing: 8) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.nftGreen)
                    Text(L10n.winner + ": " + winner.userName)
                        .font(NFTTypography.caption)

                    Spacer()

                    Text(auction.endTime.formatted(date: .abbreviated, time: .shortened))
                        .font(NFTTypography.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .nftCardStyle()
    }
}
