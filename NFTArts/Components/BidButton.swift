import SwiftUI

struct BidButton: View {
    let auction: Auction
    @EnvironmentObject var auctionService: AuctionService
    @EnvironmentObject var lang: LanguageManager
    @State private var showBidSheet = false
    @State private var isPulsing = false

    var body: some View {
        Button {
            showBidSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "gavel.fill")
                    .font(.system(size: 12))
                Text(L10n.placeBid)
                    .font(NFTTypography.caption)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                LinearGradient.nftPrimary
            )
            .clipShape(Capsule())
            .shadow(
                color: auction.isActive ? Color.nftPurple.opacity(isPulsing ? 0.5 : 0.15) : .clear,
                radius: isPulsing ? 8 : 3
            )
        }
        .disabled(!auction.isActive)
        .opacity(auction.isActive ? 1.0 : 0.5)
        .onAppear {
            guard auction.isActive else { return }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .sheet(isPresented: $showBidSheet) {
            PlaceBidSheet(auction: auction)
        }
    }
}

// MARK: - Place Bid Sheet

struct PlaceBidSheet: View {
    let auction: Auction
    @EnvironmentObject var auctionService: AuctionService
    @ObservedObject private var bidQueue = BidQueueService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var bidAmount = ""
    @State private var showConfirmation = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var placedBid: Bid?

    var minimumBid: Double {
        auction.minimumNextBid
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Artwork info
                HStack(spacing: 16) {
                    ArtworkImageView(artwork: auction.artwork)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(auction.artwork.title)
                            .font(NFTTypography.headline)
                        Text(auction.artwork.artistName)
                            .font(NFTTypography.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Current: \(auction.formattedCurrentBid)")
                            .font(NFTTypography.bid)
                            .foregroundStyle(.nftPurple)
                    }

                    Spacer()
                }
                .padding()
                .nftCardStyle()

                // Balance info
                HStack {
                    Image(systemName: "wallet.pass.fill")
                        .foregroundStyle(.nftPurple)
                    Text(L10n.yourBalance)
                        .font(NFTTypography.subheadline)
                    Spacer()
                    Text(auctionService.currentUser.formattedBalance)
                        .font(NFTTypography.bid)
                        .foregroundStyle(.nftGreen)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Pending bids banner
                if !bidQueue.pendingBids.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.orange)
                        Text(L10n.pendingBidsCount(bidQueue.pendingBids.count))
                            .font(NFTTypography.caption)
                        Spacer()
                        if bidQueue.isSyncing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Button(action: { bidQueue.syncQueue() }) {
                                Text("Sync")
                                    .font(NFTTypography.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.nftPurple)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Bid input
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.yourBid)
                        .font(NFTTypography.headline)

                    HStack {
                        TextField(String(format: "Min %.2f", minimumBid), text: $bidAmount)
                            .font(NFTTypography.price)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.plain)

                        Text("ETH")
                            .font(NFTTypography.headline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Text(L10n.minimumBid + ": \(String(format: "%.2f ETH", minimumBid))")
                        .font(NFTTypography.caption)
                        .foregroundStyle(.secondary)

                    // Quick bid buttons
                    HStack(spacing: 8) {
                        quickBidButton(amount: minimumBid)
                        quickBidButton(amount: minimumBid * 1.1)
                        quickBidButton(amount: minimumBid * 1.25)
                    }
                }

                Spacer()

                // Submit button
                Button {
                    submitBid()
                } label: {
                    Text(L10n.placeBid)
                        .font(NFTTypography.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(LinearGradient.nftPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(bidAmount.isEmpty || (Double(bidAmount) ?? 0) < minimumBid)
            }
            .padding()
            .navigationTitle(L10n.placeBid)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                }
            }
            .alert(L10n.bidPlaced, isPresented: $showConfirmation) {
                Button(L10n.ok) { dismiss() }
            } message: {
                if let bid = placedBid {
                    Text("Your bid of \(bid.formattedAmount) has been placed on \"\(auction.artwork.title)\"")
                }
            }
            .alert(L10n.bidFailed, isPresented: $showError) {
                Button(L10n.ok) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func quickBidButton(amount: Double) -> some View {
        Button {
            bidAmount = String(format: "%.2f", amount)
        } label: {
            Text(String(format: "%.2f", amount))
                .font(NFTTypography.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemBackground))
                .clipShape(Capsule())
        }
    }

    private func submitBid() {
        guard let amount = Double(bidAmount) else { return }

        let result = auctionService.placeBid(on: auction.id, amount: amount)
        switch result {
        case .success(let bid):
            placedBid = bid
            showConfirmation = true
        case .failure(let message):
            errorMessage = message
            showError = true
        }
    }
}
