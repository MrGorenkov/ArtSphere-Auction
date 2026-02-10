import SwiftUI

struct ArtworkImageView: View {
    let artwork: NFTArtwork
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geometry in
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color(.tertiarySystemBackground))
                    .shimmer()
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary.opacity(0.3))
                    }
                    .onAppear {
                        loadImage(size: geometry.size)
                    }
            }
        }
    }

    private func loadImage(size: CGSize) {
        // 1. Uploaded local image
        if artwork.imageSource == .uploaded, let data = artwork.localImageData {
            if let uiImage = UIImage(data: data) {
                withAnimation(.easeIn(duration: 0.3)) { self.image = uiImage }
                return
            }
        }

        // 2. URL-based image from backend
        if artwork.imageSource == .url, let urlString = artwork.imageURL,
           let url = URL(string: urlString) {
            Task {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    if let uiImage = UIImage(data: data) {
                        await MainActor.run {
                            withAnimation(.easeIn(duration: 0.3)) { self.image = uiImage }
                        }
                        return
                    }
                } catch {
                    // Fall through to procedural generation
                }
                // Fallback to procedural
                await generateProcedural(size: size)
            }
            return
        }

        // 3. Procedural generation (default)
        generateProceduralSync(size: size)
    }

    private func generateProceduralSync(size: CGSize) {
        let targetSize = CGSize(
            width: max(size.width * 2, 400),
            height: max(size.height * 2, 400)
        )
        DispatchQueue.global(qos: .userInitiated).async {
            let generated = MockDataService.generateArtworkImage(for: artwork, size: targetSize)
            DispatchQueue.main.async {
                withAnimation(.easeIn(duration: 0.3)) { self.image = generated }
            }
        }
    }

    private func generateProcedural(size: CGSize) async {
        let targetSize = CGSize(
            width: max(size.width * 2, 400),
            height: max(size.height * 2, 400)
        )
        let generated = await Task.detached {
            MockDataService.generateArtworkImage(for: self.artwork, size: targetSize)
        }.value
        await MainActor.run {
            withAnimation(.easeIn(duration: 0.3)) { self.image = generated }
        }
    }
}
