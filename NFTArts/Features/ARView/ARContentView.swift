import SwiftUI
import ARKit
import RealityKit

struct ARContentView: View {
    @EnvironmentObject var auctionService: AuctionService
    @EnvironmentObject var lang: LanguageManager
    @State private var showARSession = false
    @State private var selectedArtwork: NFTArtwork?
    @State private var showArtworkPicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let artwork = selectedArtwork {
                    selectedArtworkPreview(artwork)
                } else {
                    placeholderView
                }
            }
            .navigationTitle(L10n.arTitle)
            .sheet(isPresented: $showArtworkPicker) {
                ArtworkPickerSheet(
                    auctions: auctionService.auctions,
                    selectedArtwork: $selectedArtwork
                )
            }
            .fullScreenCover(isPresented: $showARSession) {
                if let artwork = selectedArtwork {
                    ARShowroomView(artwork: artwork)
                        .environmentObject(auctionService)
                }
            }
        }
    }

    private var placeholderView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "arkit")
                .font(.system(size: 80))
                .foregroundStyle(.nftPurple)

            VStack(spacing: 8) {
                Text(L10n.arViewer)
                    .font(NFTTypography.title)

                Text(L10n.arDescription)
                    .font(NFTTypography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                showArtworkPicker = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle")
                    Text(L10n.selectArtwork)
                }
                .font(NFTTypography.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(LinearGradient.nftPrimary)
                .clipShape(Capsule())
            }
            .padding(.top, 8)

            Spacer()
        }
    }

    private func selectedArtworkPreview(_ artwork: NFTArtwork) -> some View {
        VStack(spacing: 20) {
            // Preview card
            VStack(spacing: 12) {
                ArtworkImageView(artwork: artwork)
                    .frame(height: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(spacing: 4) {
                    Text(artwork.title)
                        .font(NFTTypography.headline)
                    Text(artwork.artistName)
                        .font(NFTTypography.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .nftCardStyle()
            .padding(.horizontal)

            // Action buttons
            VStack(spacing: 12) {
                Button {
                    showARSession = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                        Text(L10n.launchAR)
                    }
                    .font(NFTTypography.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(LinearGradient.nftPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    showArtworkPicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text(L10n.changeArtwork)
                    }
                    .font(NFTTypography.subheadline)
                    .foregroundStyle(.nftPurple)
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Artwork Picker Sheet

struct ArtworkPickerSheet: View {
    let auctions: [Auction]
    @Binding var selectedArtwork: NFTArtwork?
    var onSelect: ((NFTArtwork) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    ForEach(auctions) { auction in
                        Button {
                            selectedArtwork = auction.artwork
                            onSelect?(auction.artwork)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                ArtworkImageView(artwork: auction.artwork)
                                    .frame(height: 150)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay {
                                        if selectedArtwork?.id == auction.artwork.id {
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color.nftPurple, lineWidth: 3)
                                        }
                                    }

                                Text(auction.artwork.title)
                                    .font(NFTTypography.caption)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle(L10n.selectArtwork)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                }
            }
        }
    }
}
