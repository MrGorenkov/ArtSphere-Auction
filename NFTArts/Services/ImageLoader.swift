import UIKit

/// Resolves an `NFTArtwork` to a UIImage with caching and async URL loading.
///
/// Sources, in priority order:
///  1. Bundled asset (`imageName`).
///  2. Local raw data (`localImageData`).
///  3. Remote URL (`imageURL`) — fetched once via URLSession, cached in NSCache.
///  4. Procedural fallback via `MockDataService.generateArtworkImage`.
///
/// Threading: cache reads are synchronous, network fetches are async.
/// Same image is never decoded twice for the lifetime of the cache.
enum ImageLoader {

    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 64                    // ~64 paintings is plenty for one session
        c.totalCostLimit = 64 * 1024 * 1024  // ~64 MB ceiling, evicts under memory pressure
        return c
    }()

    /// Returns an immediately available image for `artwork`, without doing any network work.
    /// If the URL hasn't been fetched yet, returns a procedural placeholder so callers can
    /// render *something* and then upgrade once the real image arrives.
    static func cachedOrPlaceholder(for artwork: NFTArtwork,
                                    placeholderSize: CGSize = CGSize(width: 512, height: 512)) -> UIImage {
        if let cached = cache.object(forKey: artwork.id.uuidString as NSString) {
            return cached
        }
        if artwork.imageSource == .uploaded,
           let data = artwork.localImageData,
           let img = UIImage(data: data) {
            store(img, for: artwork)
            return img
        }
        if artwork.imageSource == .bundled,
           let img = UIImage(named: artwork.imageName) {
            store(img, for: artwork)
            return img
        }
        // URL-sourced or unresolved: return procedural placeholder, real image loads later.
        return MockDataService.generateArtworkImage(for: artwork, size: placeholderSize)
    }

    /// Resolves `artwork` to a UIImage, downloading the URL source on a background queue if needed.
    /// On success the image is cached and returned. On failure returns the procedural placeholder.
    static func loadImage(for artwork: NFTArtwork) async -> UIImage {
        if let cached = cache.object(forKey: artwork.id.uuidString as NSString) {
            return cached
        }

        // Synchronous (in-memory) sources first.
        if artwork.imageSource == .uploaded,
           let data = artwork.localImageData,
           let img = UIImage(data: data) {
            store(img, for: artwork)
            return img
        }
        if artwork.imageSource == .bundled,
           let img = UIImage(named: artwork.imageName) {
            store(img, for: artwork)
            return img
        }

        // Network case.
        if artwork.imageSource == .url,
           let urlString = artwork.imageURL,
           let url = URL(string: urlString) {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let img = UIImage(data: data) {
                    store(img, for: artwork)
                    return img
                }
            } catch {
                // Fall through to placeholder on network errors.
            }
        }

        return MockDataService.generateArtworkImage(for: artwork)
    }

    private static func store(_ image: UIImage, for artwork: NFTArtwork) {
        let cost = (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0)
        cache.setObject(image, forKey: artwork.id.uuidString as NSString, cost: cost)
    }

    /// Pre-warms the cache for the given artworks on a background queue.
    /// Skips ones already cached. Limited to URL-sourced items (others resolve instantly).
    static func prefetch(_ artworks: [NFTArtwork]) {
        for artwork in artworks where artwork.imageSource == .url {
            let key = artwork.id.uuidString as NSString
            guard cache.object(forKey: key) == nil else { continue }
            Task.detached(priority: .utility) {
                _ = await loadImage(for: artwork)
            }
        }
    }
}
