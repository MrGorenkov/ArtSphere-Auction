import UIKit
import Accelerate

enum NormalMapGenerator {

    // MARK: - Algorithm

    /// Choice of pipeline used to extract surface relief from a flat image.
    ///
    /// - `sobel`: classic first-derivative gradient filter (3×3, separable Gx/Gy). Cheap,
    ///   robust, but misses fine details and produces broad edges.
    /// - `laplacian`: Marr–Hildreth (Laplacian of Gaussian). Reacts to curvature changes
    ///   rather than slopes — picks up thin brush strokes Sobel smooths over.
    /// - `hybrid`: Depth Anything V2 (Vision Transformer, monocular depth estimation)
    ///   for global scene depth + Laplacian for fine surface texture. Combined map
    ///   captures both spatial geometry of the scene AND the relief of brush strokes —
    ///   qualitatively richer than any single classical filter.
    enum FilterAlgorithm: String {
        case sobel
        case laplacian
        case hybrid
    }

    /// Default pipeline. Hybrid uses the Neural Engine for global depth, classical
    /// Laplacian for fine detail — the strongest combination available on-device.
    /// Falls back to Laplacian automatically if the CoreML model isn't loaded.
    static var defaultAlgorithm: FilterAlgorithm = .hybrid

    // MARK: - Cache

    /// Caches per-artwork derived images. Keyed by stable identifier (e.g., artwork id).
    /// Cleared automatically by the system on memory pressure.
    private enum Cache {
        static let normalMap: NSCache<NSString, UIImage> = {
            let c = NSCache<NSString, UIImage>()
            c.countLimit = 64
            return c
        }()
        static let heightmap: NSCache<NSString, UIImage> = {
            let c = NSCache<NSString, UIImage>()
            c.countLimit = 64
            return c
        }()
        static let heatmap: NSCache<NSString, UIImage> = {
            let c = NSCache<NSString, UIImage>()
            c.countLimit = 64
            return c
        }()

        static func key(_ raw: String, suffix: String) -> NSString {
            "\(raw)#\(suffix)" as NSString
        }
    }

    /// Drops every cached map (normal/height/heatmap) for the given artwork id. Call this
    /// when the source image is replaced (e.g., URL artwork loaded after placeholder) so
    /// the next `generate*` call rebuilds from the new bytes instead of returning the
    /// placeholder-derived map.
    static func invalidate(cacheKey: String) {
        // Cover every (algorithm, strength) combination we ever cache under.
        var suffixes: [String] = ["heatmap"]
        for algo in ["sobel", "laplacian", "hybrid"] {
            suffixes.append("normal_3.5_\(algo)")
            suffixes.append("height_\(algo)")
        }
        for suffix in suffixes {
            let key = Cache.key(cacheKey, suffix: suffix)
            Cache.normalMap.removeObject(forKey: key)
            Cache.heightmap.removeObject(forKey: key)
            Cache.heatmap.removeObject(forKey: key)
        }
        DepthEstimator.shared.invalidate(cacheKey: cacheKey)
    }

    /// Generates a normal map from a 2D image.
    ///
    /// Dispatches to the algorithm-specific pipeline (Sobel / Laplacian / Hybrid).
    /// Hybrid falls back to Laplacian if the CoreML depth model isn't available
    /// (e.g. on simulator without Neural Engine, or if the resource didn't ship).
    static func generate(
        from image: UIImage,
        strength: Float = 3.5,
        cacheKey: String? = nil,
        algorithm: FilterAlgorithm = NormalMapGenerator.defaultAlgorithm
    ) -> UIImage {
        let cacheSuffix = "normal_\(strength)_\(algorithm.rawValue)"
        if let raw = cacheKey,
           let cached = Cache.normalMap.object(forKey: Cache.key(raw, suffix: cacheSuffix)) {
            return cached
        }

        let result: UIImage
        switch algorithm {
        case .sobel:
            result = generateSobel(from: image, strength: strength)
        case .laplacian:
            result = generateLaplacian(from: image, strength: strength)
        case .hybrid:
            if DepthEstimator.shared.isAvailable {
                result = generateHybrid(from: image, strength: strength, cacheKey: cacheKey)
            } else {
                result = generateLaplacian(from: image, strength: strength)
            }
        }
        if let raw = cacheKey {
            Cache.normalMap.setObject(result, forKey: Cache.key(raw, suffix: cacheSuffix))
        }
        return result
    }

    // MARK: - Sobel pipeline (legacy)

    /// Classical Sobel-based normal map. Cheap, robust, finds broad edges.
    private static func generateSobel(from image: UIImage, strength: Float) -> UIImage {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            MetricsService.shared.record(category: "3d_rendering", name: "normal_map_generation_ms", value: elapsed, unit: "ms")
        }
        guard let cgImage = image.cgImage else { return image }

        let width = cgImage.width
        let height = cgImage.height

        // Convert to grayscale buffer
        guard var grayscaleBuffer = createGrayscaleBuffer(from: cgImage, width: width, height: height) else {
            return image
        }

        // Apply Gaussian blur to emphasize broad brushstrokes over noise
        var blurredBuffer = createEmptyBuffer(width: width, height: height)
        let gaussianKernel: [Float] = [
            1, 2, 1,
            2, 4, 2,
            1, 2, 1
        ].map { $0 / 16.0 }

        vImageConvolve_PlanarF(
            &grayscaleBuffer, &blurredBuffer, nil, 0, 0,
            gaussianKernel, 3, 3,
            0, vImage_Flags(kvImageEdgeExtend)
        )

        // Sobel filter for gradients (on blurred buffer for cleaner strokes)
        var sobelX = createEmptyBuffer(width: width, height: height)
        var sobelY = createEmptyBuffer(width: width, height: height)

        defer {
            grayscaleBuffer.data.deallocate()
            blurredBuffer.data.deallocate()
            sobelX.data.deallocate()
            sobelY.data.deallocate()
        }

        // Apply Sobel convolution on blurred buffer
        let sobelKernelX: [Float] = [-1, 0, 1, -2, 0, 2, -1, 0, 1]
        let sobelKernelY: [Float] = [-1, -2, -1, 0, 0, 0, 1, 2, 1]

        vImageConvolve_PlanarF(
            &blurredBuffer, &sobelX, nil, 0, 0,
            sobelKernelX, 3, 3,
            0,
            vImage_Flags(kvImageEdgeExtend)
        )

        vImageConvolve_PlanarF(
            &blurredBuffer, &sobelY, nil, 0, 0,
            sobelKernelY, 3, 3,
            0,
            vImage_Flags(kvImageEdgeExtend)
        )

        // Generate normal map RGBA buffer
        let bytesPerRow = width * 4
        let totalBytes = height * bytesPerRow
        let normalData = UnsafeMutablePointer<UInt8>.allocate(capacity: totalBytes)

        let dxPtr = sobelX.data.assumingMemoryBound(to: Float.self)
        let dyPtr = sobelY.data.assumingMemoryBound(to: Float.self)

        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                let pixelOffset = y * bytesPerRow + x * 4

                let dx = dxPtr[idx] * strength
                let dy = dyPtr[idx] * strength
                let dz: Float = 1.0

                // Normalize
                let length = sqrtf(dx * dx + dy * dy + dz * dz)
                let nx = dx / length
                let ny = dy / length
                let nz = dz / length

                // Map from [-1, 1] to [0, 255]
                normalData[pixelOffset + 0] = UInt8(clamping: Int((nx * 0.5 + 0.5) * 255))
                normalData[pixelOffset + 1] = UInt8(clamping: Int((ny * 0.5 + 0.5) * 255))
                normalData[pixelOffset + 2] = UInt8(clamping: Int((nz * 0.5 + 0.5) * 255))
                normalData[pixelOffset + 3] = 255
            }
        }

        // Create CGImage from normal data
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: normalData,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let normalCGImage = context.makeImage()
        else {
            normalData.deallocate()
            return image
        }

        let result = UIImage(cgImage: normalCGImage)
        normalData.deallocate()
        return result
    }

    // MARK: - Laplacian pipeline

    /// Marr–Hildreth pipeline: Gaussian smoothing followed by the Laplacian operator.
    /// Reacts to **second-order** changes in brightness, so it isolates the sharp ridges
    /// of brush strokes (where curvature flips) rather than the broad slopes Sobel finds.
    /// Less stable on noisy input, but we already pre-blur with a 3×3 Gaussian.
    ///
    /// To turn the scalar Laplacian into a 2-component gradient suitable for a normal
    /// map, we compute the second partial derivatives ∂²/∂x² and ∂²/∂y² separately and
    /// treat them as (nx, ny) just like Sobel's (Gx, Gy).
    private static func generateLaplacian(from image: UIImage, strength: Float) -> UIImage {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            MetricsService.shared.record(category: "3d_rendering", name: "normal_map_laplacian_ms", value: elapsed, unit: "ms")
        }
        guard let cgImage = image.cgImage else { return image }
        let width = cgImage.width
        let height = cgImage.height
        guard var gray = createGrayscaleBuffer(from: cgImage, width: width, height: height) else { return image }
        var blurred = createEmptyBuffer(width: width, height: height)
        let gauss: [Float] = [1, 2, 1, 2, 4, 2, 1, 2, 1].map { $0 / 16.0 }
        vImageConvolve_PlanarF(&gray, &blurred, nil, 0, 0, gauss, 3, 3, 0, vImage_Flags(kvImageEdgeExtend))

        // ∂²/∂x² and ∂²/∂y² kernels — second-order finite differences.
        var dxx = createEmptyBuffer(width: width, height: height)
        var dyy = createEmptyBuffer(width: width, height: height)
        let laplaceX: [Float] = [0, 0, 0, 1, -2, 1, 0, 0, 0]
        let laplaceY: [Float] = [0, 1, 0, 0, -2, 0, 0, 1, 0]
        vImageConvolve_PlanarF(&blurred, &dxx, nil, 0, 0, laplaceX, 3, 3, 0, vImage_Flags(kvImageEdgeExtend))
        vImageConvolve_PlanarF(&blurred, &dyy, nil, 0, 0, laplaceY, 3, 3, 0, vImage_Flags(kvImageEdgeExtend))

        defer {
            gray.data.deallocate()
            blurred.data.deallocate()
            dxx.data.deallocate()
            dyy.data.deallocate()
        }

        return buildNormalImage(
            dx: dxx.data.assumingMemoryBound(to: Float.self),
            dy: dyy.data.assumingMemoryBound(to: Float.self),
            width: width, height: height,
            strength: strength
        ) ?? image
    }

    // MARK: - Hybrid pipeline (Depth Anything V2 + Laplacian detail)

    /// Two-stream pipeline:
    /// 1. Global depth from Depth Anything V2 (CoreML on Neural Engine) — captures
    ///    spatial geometry of the *scene* (foreground/background, perspective).
    /// 2. Fine-grain Laplacian gradient on the original image — preserves the texture
    ///    of brush strokes that flat depth misses.
    /// 3. Per-pixel weighted sum (`0.7 * depth + 0.3 * laplacian`) becomes a single
    ///    combined heightmap; finite differences of that height field yield the normals.
    private static func generateHybrid(
        from image: UIImage,
        strength: Float,
        cacheKey: String?
    ) -> UIImage {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            MetricsService.shared.record(category: "3d_rendering", name: "normal_map_hybrid_ms", value: elapsed, unit: "ms")
        }

        guard let depth = DepthEstimator.shared.depthMap(for: image, cacheKey: cacheKey),
              let depthCG = depth.cgImage,
              let sourceCG = image.cgImage else {
            return generateLaplacian(from: image, strength: strength)
        }

        let width = sourceCG.width
        let height = sourceCG.height

        // Pull depth (already same dimensions as source — DepthEstimator resamples).
        guard var depthBuf = createGrayscaleBuffer(from: depthCG, width: width, height: height) else {
            return generateLaplacian(from: image, strength: strength)
        }
        guard var sourceBuf = createGrayscaleBuffer(from: sourceCG, width: width, height: height) else {
            depthBuf.data.deallocate()
            return generateLaplacian(from: image, strength: strength)
        }
        var blurred = createEmptyBuffer(width: width, height: height)
        let gauss: [Float] = [1, 2, 1, 2, 4, 2, 1, 2, 1].map { $0 / 16.0 }
        vImageConvolve_PlanarF(&sourceBuf, &blurred, nil, 0, 0, gauss, 3, 3, 0, vImage_Flags(kvImageEdgeExtend))

        var laplaceXBuf = createEmptyBuffer(width: width, height: height)
        var laplaceYBuf = createEmptyBuffer(width: width, height: height)
        let kernelX: [Float] = [0, 0, 0, 1, -2, 1, 0, 0, 0]
        let kernelY: [Float] = [0, 1, 0, 0, -2, 0, 0, 1, 0]
        vImageConvolve_PlanarF(&blurred, &laplaceXBuf, nil, 0, 0, kernelX, 3, 3, 0, vImage_Flags(kvImageEdgeExtend))
        vImageConvolve_PlanarF(&blurred, &laplaceYBuf, nil, 0, 0, kernelY, 3, 3, 0, vImage_Flags(kvImageEdgeExtend))

        defer {
            depthBuf.data.deallocate()
            sourceBuf.data.deallocate()
            blurred.data.deallocate()
            laplaceXBuf.data.deallocate()
            laplaceYBuf.data.deallocate()
        }

        // Take finite differences of the depth field along X and Y so we have a real
        // gradient. The depth itself is "how close" not "how much it changes".
        var depthDX = createEmptyBuffer(width: width, height: height)
        var depthDY = createEmptyBuffer(width: width, height: height)
        let sobelX: [Float] = [-1, 0, 1, -2, 0, 2, -1, 0, 1]
        let sobelY: [Float] = [-1, -2, -1, 0, 0, 0, 1, 2, 1]
        vImageConvolve_PlanarF(&depthBuf, &depthDX, nil, 0, 0, sobelX, 3, 3, 0, vImage_Flags(kvImageEdgeExtend))
        vImageConvolve_PlanarF(&depthBuf, &depthDY, nil, 0, 0, sobelY, 3, 3, 0, vImage_Flags(kvImageEdgeExtend))

        defer {
            depthDX.data.deallocate()
            depthDY.data.deallocate()
        }

        // Weighted combine: 0.7 * depth-grad + 0.3 * laplacian-detail.
        let count = width * height
        let combinedDX = UnsafeMutablePointer<Float>.allocate(capacity: count)
        let combinedDY = UnsafeMutablePointer<Float>.allocate(capacity: count)
        defer {
            combinedDX.deallocate()
            combinedDY.deallocate()
        }
        let dxDepth = depthDX.data.assumingMemoryBound(to: Float.self)
        let dyDepth = depthDY.data.assumingMemoryBound(to: Float.self)
        let dxLap = laplaceXBuf.data.assumingMemoryBound(to: Float.self)
        let dyLap = laplaceYBuf.data.assumingMemoryBound(to: Float.self)

        var w1: Float = 0.7
        var w2: Float = 0.3
        vDSP_vsmsma(dxDepth, 1, &w1, dxLap, 1, &w2, combinedDX, 1, vDSP_Length(count))
        vDSP_vsmsma(dyDepth, 1, &w1, dyLap, 1, &w2, combinedDY, 1, vDSP_Length(count))

        return buildNormalImage(
            dx: combinedDX, dy: combinedDY,
            width: width, height: height,
            strength: strength
        ) ?? image
    }

    // MARK: - Normal map builder (shared by all pipelines)

    /// Takes a pair of (∂h/∂x, ∂h/∂y) gradient buffers and emits an RGBA normal map
    /// in OpenGL conventions (R = nx, G = ny, B = nz, A = 255).
    private static func buildNormalImage(
        dx: UnsafePointer<Float>,
        dy: UnsafePointer<Float>,
        width: Int,
        height: Int,
        strength: Float
    ) -> UIImage? {
        let bytesPerRow = width * 4
        let totalBytes = height * bytesPerRow
        let normalData = UnsafeMutablePointer<UInt8>.allocate(capacity: totalBytes)

        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                let pixelOffset = y * bytesPerRow + x * 4
                let gx = dx[idx] * strength
                let gy = dy[idx] * strength
                let gz: Float = 1.0
                let length = sqrtf(gx * gx + gy * gy + gz * gz)
                let nx = gx / length
                let ny = gy / length
                let nz = gz / length
                normalData[pixelOffset + 0] = UInt8(clamping: Int((nx * 0.5 + 0.5) * 255))
                normalData[pixelOffset + 1] = UInt8(clamping: Int((ny * 0.5 + 0.5) * 255))
                normalData[pixelOffset + 2] = UInt8(clamping: Int((nz * 0.5 + 0.5) * 255))
                normalData[pixelOffset + 3] = 255
            }
        }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: normalData,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let cg = context.makeImage()
        else {
            normalData.deallocate()
            return nil
        }
        let img = UIImage(cgImage: cg)
        normalData.deallocate()
        return img
    }

    // MARK: - Texture Complexity Metric

    /// Calculates the average gradient magnitude across the image using Sobel X/Y.
    /// Returns a value normalized to 0.0 (flat/uniform) – 1.0 (very complex texture).
    static func calculateTextureMetric(from image: UIImage) -> Double? {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            MetricsService.shared.record(category: "image_analysis", name: "texture_metric_ms", value: elapsed, unit: "ms")
        }
        guard let cgImage = image.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        let pixelCount = width * height
        guard pixelCount > 0 else { return nil }

        guard var grayscaleBuffer = createGrayscaleBuffer(from: cgImage, width: width, height: height) else {
            return nil
        }

        var sobelX = createEmptyBuffer(width: width, height: height)
        var sobelY = createEmptyBuffer(width: width, height: height)

        defer {
            grayscaleBuffer.data.deallocate()
            sobelX.data.deallocate()
            sobelY.data.deallocate()
        }

        let sobelKernelX: [Float] = [-1, 0, 1, -2, 0, 2, -1, 0, 1]
        let sobelKernelY: [Float] = [-1, -2, -1, 0, 0, 0, 1, 2, 1]

        vImageConvolve_PlanarF(&grayscaleBuffer, &sobelX, nil, 0, 0,
                               sobelKernelX, 3, 3, 0, vImage_Flags(kvImageEdgeExtend))
        vImageConvolve_PlanarF(&grayscaleBuffer, &sobelY, nil, 0, 0,
                               sobelKernelY, 3, 3, 0, vImage_Flags(kvImageEdgeExtend))

        let dxPtr = sobelX.data.assumingMemoryBound(to: Float.self)
        let dyPtr = sobelY.data.assumingMemoryBound(to: Float.self)

        // Compute average gradient magnitude: mean(sqrt(Gx² + Gy²))
        var totalMagnitude: Double = 0
        for i in 0..<pixelCount {
            let gx = Double(dxPtr[i])
            let gy = Double(dyPtr[i])
            totalMagnitude += sqrt(gx * gx + gy * gy)
        }

        let avgMagnitude = totalMagnitude / Double(pixelCount)
        // Sobel max theoretical magnitude ≈ 4.0 (for grayscale 0–1 input).
        // Normalize so typical textures map into 0–1 range.
        let maxExpected = 1.5
        return min(avgMagnitude / maxExpected, 1.0)
    }

    /// Generates a heatmap image from gradient magnitudes (blue→yellow→red).
    /// Used to visualize texture complexity per-pixel.
    static func generateComplexityHeatmap(from image: UIImage, cacheKey: String? = nil) -> UIImage? {
        if let raw = cacheKey,
           let cached = Cache.heatmap.object(forKey: Cache.key(raw, suffix: "heatmap")) {
            return cached
        }
        guard let cgImage = image.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        let pixelCount = width * height
        guard pixelCount > 0 else { return nil }

        guard var grayscaleBuffer = createGrayscaleBuffer(from: cgImage, width: width, height: height) else {
            return nil
        }

        var sobelX = createEmptyBuffer(width: width, height: height)
        var sobelY = createEmptyBuffer(width: width, height: height)

        defer {
            grayscaleBuffer.data.deallocate()
            sobelX.data.deallocate()
            sobelY.data.deallocate()
        }

        let sobelKernelX: [Float] = [-1, 0, 1, -2, 0, 2, -1, 0, 1]
        let sobelKernelY: [Float] = [-1, -2, -1, 0, 0, 0, 1, 2, 1]

        vImageConvolve_PlanarF(&grayscaleBuffer, &sobelX, nil, 0, 0,
                               sobelKernelX, 3, 3, 0, vImage_Flags(kvImageEdgeExtend))
        vImageConvolve_PlanarF(&grayscaleBuffer, &sobelY, nil, 0, 0,
                               sobelKernelY, 3, 3, 0, vImage_Flags(kvImageEdgeExtend))

        let dxPtr = sobelX.data.assumingMemoryBound(to: Float.self)
        let dyPtr = sobelY.data.assumingMemoryBound(to: Float.self)

        // Find max magnitude for normalization
        var maxMag: Float = 0
        for i in 0..<pixelCount {
            let gx = dxPtr[i]
            let gy = dyPtr[i]
            let mag = sqrtf(gx * gx + gy * gy)
            if mag > maxMag { maxMag = mag }
        }
        if maxMag < 0.001 { maxMag = 1.0 }

        // Generate RGBA heatmap
        let bytesPerRow = width * 4
        let heatmapData = UnsafeMutablePointer<UInt8>.allocate(capacity: height * bytesPerRow)

        for i in 0..<pixelCount {
            let gx = dxPtr[i]
            let gy = dyPtr[i]
            let mag = sqrtf(gx * gx + gy * gy)
            let t = min(mag / maxMag, 1.0)  // 0 = low, 1 = high

            // Blue (0,0,1) → Yellow (1,1,0) → Red (1,0,0)
            let r: Float
            let g: Float
            let b: Float
            if t < 0.5 {
                let s = t / 0.5
                r = s
                g = s
                b = 1.0 - s
            } else {
                let s = (t - 0.5) / 0.5
                r = 1.0
                g = 1.0 - s
                b = 0.0
            }

            let offset = i * 4
            // map to y,x
            let y = i / width
            let x = i % width
            let pixelOffset = y * bytesPerRow + x * 4
            heatmapData[pixelOffset + 0] = UInt8(clamping: Int(r * 255))
            heatmapData[pixelOffset + 1] = UInt8(clamping: Int(g * 255))
            heatmapData[pixelOffset + 2] = UInt8(clamping: Int(b * 255))
            heatmapData[pixelOffset + 3] = 255
        }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: heatmapData,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let heatmapCGImage = context.makeImage()
        else {
            heatmapData.deallocate()
            return nil
        }

        let result = UIImage(cgImage: heatmapCGImage)
        heatmapData.deallocate()
        if let raw = cacheKey {
            Cache.heatmap.setObject(result, forKey: Cache.key(raw, suffix: "heatmap"))
        }
        return result
    }

    // MARK: - Private Helpers

    private static func createGrayscaleBuffer(from cgImage: CGImage, width: Int, height: Int) -> vImage_Buffer? {
        let floatCount = width * height
        let data = UnsafeMutablePointer<Float>.allocate(capacity: floatCount)

        // Get pixel data
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            data.deallocate()
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let pixelData = context.data else {
            data.deallocate()
            return nil
        }

        let pixels = pixelData.bindMemory(to: UInt8.self, capacity: width * height * 4)

        for i in 0..<floatCount {
            let r = Float(pixels[i * 4]) / 255.0
            let g = Float(pixels[i * 4 + 1]) / 255.0
            let b = Float(pixels[i * 4 + 2]) / 255.0
            // Luminance formula
            data[i] = 0.299 * r + 0.587 * g + 0.114 * b
        }

        return vImage_Buffer(
            data: data,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: width * MemoryLayout<Float>.stride
        )
    }

    private static func createEmptyBuffer(width: Int, height: Int) -> vImage_Buffer {
        let data = UnsafeMutablePointer<Float>.allocate(capacity: width * height)
        data.initialize(repeating: 0, count: width * height)
        return vImage_Buffer(
            data: data,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: width * MemoryLayout<Float>.stride
        )
    }

    // MARK: - Heightmap for Displacement

    /// Generates a grayscale heightmap from an image for displacement mapping in SceneKit.
    static func generateHeightmap(
        from image: UIImage,
        cacheKey: String? = nil,
        algorithm: FilterAlgorithm = NormalMapGenerator.defaultAlgorithm
    ) -> UIImage {
        let suffix = "height_\(algorithm.rawValue)"
        if let raw = cacheKey,
           let cached = Cache.heightmap.object(forKey: Cache.key(raw, suffix: suffix)) {
            return cached
        }
        // In hybrid mode the displacement map is the depth estimation itself: brighter
        // pixels (closer) get pushed outwards by SceneKit's displacement intensity, so
        // perspective in the painting becomes physical relief on the SCNPlane.
        if algorithm == .hybrid, DepthEstimator.shared.isAvailable,
           let depth = DepthEstimator.shared.depthMap(for: image, cacheKey: cacheKey) {
            if let raw = cacheKey {
                Cache.heightmap.setObject(depth, forKey: Cache.key(raw, suffix: suffix))
            }
            return depth
        }
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            MetricsService.shared.record(category: "3d_rendering", name: "heightmap_generation_ms", value: elapsed, unit: "ms")
        }
        guard let cgImage = image.cgImage else { return image }
        let width = cgImage.width
        let height = cgImage.height
        guard var grayscaleBuffer = createGrayscaleBuffer(from: cgImage, width: width, height: height) else {
            return image
        }
        defer { grayscaleBuffer.data.deallocate() }

        let bytesPerRow = width
        let data = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height)
        let ptr = grayscaleBuffer.data.assumingMemoryBound(to: Float.self)
        for i in 0..<(width * height) {
            data[i] = UInt8(clamping: Int(ptr[i] * 255))
        }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.linearGray),
              let context = CGContext(data: data, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let cgResult = context.makeImage() else {
            data.deallocate()
            return image
        }
        let result = UIImage(cgImage: cgResult)
        data.deallocate()
        if let raw = cacheKey {
            Cache.heightmap.setObject(result, forKey: Cache.key(raw, suffix: "height"))
        }
        return result
    }
}
