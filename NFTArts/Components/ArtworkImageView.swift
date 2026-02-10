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
                    .overlay {
                        ProgressView()
                    }
                    .onAppear {
                        loadImage(size: geometry.size)
                    }
            }
        }
    }

    private func loadImage(size: CGSize) {
        // Check if artwork has uploaded image data
        if artwork.imageSource == .uploaded, let data = artwork.localImageData {
            if let uiImage = UIImage(data: data) {
                withAnimation(.easeIn(duration: 0.3)) {
                    self.image = uiImage
                }
                return
            }
        }

        // Procedural generation
        let targetSize = CGSize(
            width: max(size.width * 2, 400),
            height: max(size.height * 2, 400)
        )
        DispatchQueue.global(qos: .userInitiated).async {
            let generated = MockDataService.generateArtworkImage(for: artwork, size: targetSize)
            DispatchQueue.main.async {
                withAnimation(.easeIn(duration: 0.3)) {
                    self.image = generated
                }
            }
        }
    }
}
