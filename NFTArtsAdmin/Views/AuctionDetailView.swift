import SwiftUI

struct AuctionDetailView: View {
    let auction: AdminAuction
    let bids: [AdminBid]
    let isLoadingBids: Bool
    let onCancel: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Artwork image
                AsyncImage(url: auction.artworkImageUrl.flatMap { URL(string: $0) }) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    Rectangle()
                        .fill(Color.purple.opacity(0.1))
                        .frame(height: 180)
                        .overlay(Image(systemName: "photo.artframe").font(.largeTitle).foregroundColor(.purple.opacity(0.3)))
                }
                .frame(maxHeight: 200)
                .cornerRadius(10)

                // Title
                Text(auction.artworkTitle)
                    .font(.title3)
                    .fontWeight(.bold)

                HStack {
                    StatusBadge(status: auction.status)
                    Spacer()
                    if let winner = auction.winnerName {
                        HStack(spacing: 4) {
                            Image(systemName: "crown.fill")
                                .font(.caption)
                                .foregroundColor(.yellow)
                            Text(winner)
                                .font(.caption)
                        }
                    }
                }

                Divider()

                // Info
                DetailRow(label: "Начальная", value: String(format: "%.2f ETH", auction.startingPrice))
                DetailRow(label: "Текущая", value: String(format: "%.2f ETH", auction.currentBid))
                if let reserve = auction.reservePrice {
                    DetailRow(label: "Резерв", value: String(format: "%.2f ETH", reserve))
                }
                DetailRow(label: "Шаг", value: String(format: "%.3f ETH", auction.bidStep))
                DetailRow(label: "Ставок", value: "\(auction.bidCount)")
                DetailRow(label: "Начало", value: formatDate(auction.startTime))
                DetailRow(label: "Конец", value: formatDate(auction.endTime))
                if let creator = auction.creatorName {
                    DetailRow(label: "Создатель", value: creator)
                }

                // Cancel button
                if auction.status == "active" || auction.status == "upcoming" {
                    Button(action: onCancel) {
                        Label("Отменить аукцион", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.large)
                }

                Divider()

                // Bids
                Text("История ставок")
                    .font(.headline)

                if isLoadingBids {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if bids.isEmpty {
                    Text("Нет ставок")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    ForEach(bids) { bid in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bid.userName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(formatDate(bid.timestamp))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Text(String(format: "%.3f ETH", bid.amount))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.purple)
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
            }
            .padding(16)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func formatDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return iso }
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return df.string(from: date)
    }
}
