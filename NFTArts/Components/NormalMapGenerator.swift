import UIKit
import Accelerate

enum NormalMapGenerator {
    /// Generates a normal map from a 2D image using Sobel filter for edge detection.
    /// The image is converted to grayscale as a height map, then gradients
    /// are calculated to produce normal vectors encoded as RGB.
    static func generate(from image: UIImage, strength: Float = 3.5) -> UIImage {
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
    static func generateComplexityHeatmap(from image: UIImage) -> UIImage? {
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
    static func generateHeightmap(from image: UIImage) -> UIImage {
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
        return result
    }
}
