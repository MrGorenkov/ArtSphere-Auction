import UIKit
import Accelerate

enum NormalMapGenerator {
    /// Generates a normal map from a 2D image using Sobel filter for edge detection.
    /// The image is converted to grayscale as a height map, then gradients
    /// are calculated to produce normal vectors encoded as RGB.
    static func generate(from image: UIImage, strength: Float = 2.0) -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        let width = cgImage.width
        let height = cgImage.height

        // Convert to grayscale buffer
        guard var grayscaleBuffer = createGrayscaleBuffer(from: cgImage, width: width, height: height) else {
            return image
        }

        // Sobel filter for gradients
        var sobelX = createEmptyBuffer(width: width, height: height)
        var sobelY = createEmptyBuffer(width: width, height: height)

        defer {
            grayscaleBuffer.data.deallocate()
            sobelX.data.deallocate()
            sobelY.data.deallocate()
        }

        // Apply Sobel convolution
        let sobelKernelX: [Float] = [-1, 0, 1, -2, 0, 2, -1, 0, 1]
        let sobelKernelY: [Float] = [-1, -2, -1, 0, 0, 0, 1, 2, 1]

        vImageConvolve_PlanarF(
            &grayscaleBuffer, &sobelX, nil, 0, 0,
            sobelKernelX, 3, 3,
            0, // backgroundColor
            vImage_Flags(kvImageEdgeExtend)
        )

        vImageConvolve_PlanarF(
            &grayscaleBuffer, &sobelY, nil, 0, 0,
            sobelKernelY, 3, 3,
            0, // backgroundColor
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
}
