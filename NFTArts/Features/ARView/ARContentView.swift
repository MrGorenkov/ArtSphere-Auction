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
                    ARViewerRepresentable(artwork: artwork)
                        .ignoresSafeArea()
                        .overlay(alignment: .topTrailing) {
                            Button {
                                showARSession = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 30))
                                    .foregroundStyle(.white)
                                    .shadow(radius: 4)
                            }
                            .padding(20)
                        }
                        .overlay(alignment: .bottom) {
                            Text(L10n.tapToPlace)
                                .font(NFTTypography.subheadline)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .padding(.bottom, 40)
                        }
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

// MARK: - AR Viewer (ARKit + RealityKit)

struct ARViewerRepresentable: UIViewRepresentable {
    let artwork: NFTArtwork

    func makeCoordinator() -> Coordinator {
        Coordinator(artwork: artwork)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // Configure AR session
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        arView.session.run(config)

        // Add tap gesture for placing artwork
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
        context.coordinator.arView = arView

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    class Coordinator: NSObject {
        let artwork: NFTArtwork
        weak var arView: ARView?
        private var hasPlaced = false

        init(artwork: NFTArtwork) {
            self.artwork = artwork
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView = arView else { return }

            let location = gesture.location(in: arView)

            // Raycast to find a surface
            let results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any)

            guard let firstResult = results.first else { return }

            // Create artwork entity
            let artworkImage = MockDataService.generateArtworkImage(for: artwork, size: CGSize(width: 512, height: 512))

            // Create a plane mesh
            let mesh = MeshResource.generatePlane(width: 0.4, height: 0.4)

            // Create material with artwork texture
            var material = SimpleMaterial()
            if let cgImage = artworkImage.cgImage,
               let texture = try? TextureResource.generate(from: cgImage, options: .init(semantic: .color)) {
                material.color = .init(tint: .white, texture: .init(texture))
            }

            let modelEntity = ModelEntity(mesh: mesh, materials: [material])

            // Add frame
            let frameMesh = MeshResource.generateBox(width: 0.42, height: 0.01, depth: 0.42, cornerRadius: 0.005)
            var frameMaterial = SimpleMaterial()
            frameMaterial.color = .init(tint: UIColor(white: 0.15, alpha: 1.0))
            frameMaterial.metallic = .float(0.8)
            frameMaterial.roughness = .float(0.3)
            let frameEntity = ModelEntity(mesh: frameMesh, materials: [frameMaterial])
            frameEntity.position = [0, -0.005, 0]

            // Create anchor
            let anchor = AnchorEntity(world: firstResult.worldTransform)
            anchor.addChild(modelEntity)
            anchor.addChild(frameEntity)

            // Remove previous if already placed
            if hasPlaced {
                arView.scene.anchors.removeAll()
            }

            arView.scene.addAnchor(anchor)
            hasPlaced = true
        }
    }
}
