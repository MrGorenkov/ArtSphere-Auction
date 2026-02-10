import SwiftUI

struct AuctionCardView: View {
    let auction: Auction
    @State private var dragOffset: CGSize = .zero
    @State private var isPressed = false

    var body: some View {
        VStack(spacing: 0) {
            // 3D Artwork Preview
            artwork3DPreview
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    statusBadge
                }
                .overlay(alignment: .topLeading) {
                    blockchainBadge
                }

            // Info Section
            infoSection
                .padding(16)
        }
        .nftCardStyle()
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.3), value: isPressed)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }

    // MARK: - 3D Artwork Preview with parallax

    private var artwork3DPreview: some View {
        GeometryReader { geometry in
            ArtworkImageView(artwork: auction.artwork)
                .overlay {
                    // Specular highlight effect based on drag
                    RadialGradient(
                        colors: [.white.opacity(0.15), .clear],
                        center: UnitPoint(
                            x: 0.5 + dragOffset.width / 500,
                            y: 0.5 + dragOffset.height / 500
                        ),
                        startRadius: 0,
                        endRadius: 200
                    )
                }
                .rotation3DEffect(
                    .degrees(Double(dragOffset.width) / 20),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.5
                )
                .rotation3DEffect(
                    .degrees(Double(-dragOffset.height) / 20),
                    axis: (x: 1, y: 0, z: 0),
                    perspective: 0.5
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            withAnimation(.interactiveSpring()) {
                                dragOffset = value.translation
                            }
                        }
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                                dragOffset = .zero
                            }
                        }
                )
        }
    }

    // MARK: - Status Badge

    private var statusBadge: some View {
        Text(L10n.statusName(auction.status))
            .font(NFTTypography.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(statusColor.opacity(0.9))
            .foregroundStyle(.white)
            .clipShape(Capsule())
            .padding(12)
    }

    private var statusColor: Color {
        switch auction.status {
        case .active: return .nftGreen
        case .upcoming: return .nftBlue
        case .ended: return .gray
        case .sold: return .nftOrange
        }
    }

    // MARK: - Blockchain Badge

    private var blockchainBadge: some View {
        Text(auction.artwork.blockchain.rawValue)
            .font(NFTTypography.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .nftGlassStyle()
            .foregroundStyle(.white)
            .padding(12)
    }

    // MARK: - Info Section

    private var infoSection: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(auction.artwork.title)
                        .font(NFTTypography.headline)
                        .lineLimit(1)

                    Text(auction.artwork.artistName)
                        .font(NFTTypography.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: auction.artwork.category.iconName)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.currentBid)
                        .font(NFTTypography.caption)
                        .foregroundStyle(.secondary)

                    Text(auction.formattedCurrentBid)
                        .font(NFTTypography.price)
                        .foregroundStyle(.nftPurple)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(L10n.endsIn)
                        .font(NFTTypography.caption)
                        .foregroundStyle(.secondary)

                    CountdownTimerView(endTime: auction.endTime, compact: false)
                }
            }

            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 12))
                    Text(L10n.bidsCount(auction.bidCount))
                        .font(NFTTypography.caption)
                }
                .foregroundStyle(.secondary)

                Spacer()

                BidButton(auction: auction)
            }
        }
    }
}
