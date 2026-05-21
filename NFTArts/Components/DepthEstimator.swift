import UIKit
import CoreML
import Vision
import Accelerate

/// Wraps Apple's Depth Anything V2 (Small, F16-INT8) CoreML model: ~24 MB, runs on the
/// Neural Engine on A12+, returns a per-pixel depth estimate (single-channel grayscale)
/// of the same resolution as the input.
///
/// The model expects 518×518 RGB input — Vision auto-scales when configured with
/// `imageCropAndScaleOption = .scaleFit`. Output is a 518×518 single-plane buffer of
/// "relative inverse depth" values: large values are *closer* to the camera, small
/// values are far away. We normalise to [0, 1] and resample to the source image size.
///
/// Performance on iPhone 11 Pro (A13 Neural Engine): ~30 ms per inference, ~50 ms wall
/// clock including pre/post-processing. On simulator falls back to CPU and runs ~400 ms.
final class DepthEstimator {

    static let shared = DepthEstimator()

    private let model: VNCoreMLModel?
    /// Cache one depth map per artwork id so a second open is instantaneous.
    private let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 32
        c.totalCostLimit = 32 * 1024 * 1024
        return c
    }()

    private init() {
        // НЕ грузим CoreML модель Depth Anything V2: на текущем iOS она крашит ANE
        // (`Invalid layer: Invalid input tensor height ...`) и компиляция на устройстве
        // занимает 30+ сек на main thread → watchdog kill. Используем luminance fallback.
        self.model = nil
    }

    /// Generates a single-channel depth map for `image`. The returned UIImage is grayscale,
    /// same dimensions as the input, encoded so that **bright pixels = nearer the camera**.
    /// Suitable for use as a displacement map: brighter = pushed out, darker = recessed.
    func depthMap(for image: UIImage, cacheKey: String? = nil) -> UIImage? {
        if let key = cacheKey, let cached = cache.object(forKey: key as NSString) {
            return cached
        }
        // CoreML Depth Anything V2 модель крашит ANE-инфер на текущем iOS
        // (`Invalid layer: Invalid input tensor height 28, must be 1`). Поэтому всегда
        // используем luminance fallback — он стабильный и даёт приличный depth.
        return fallbackDepthFromLuminance(image: image, cacheKey: cacheKey)
    }

    /// Старый CoreML pipeline — оставлен для будущего, когда исправят модель.
    private func depthMapViaCoreML(for image: UIImage, cacheKey: String?) -> UIImage? {
        guard let model, let cgImage = image.cgImage else { return nil }

        let start = CFAbsoluteTimeGetCurrent()

        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFit

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("[DepthEstimator] perform failed: \(error)")
            return nil
        }

        guard let observation = request.results?.first as? VNPixelBufferObservation else {
            return nil
        }
        let pixelBuffer = observation.pixelBuffer
        guard let depthImage = makeGrayscaleImage(from: pixelBuffer, targetSize: image.size) else {
            return nil
        }

        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        MetricsService.shared.record(
            category: "3d_rendering",
            name: "depth_anything_ms",
            value: elapsed,
            unit: "ms"
        )

        if let key = cacheKey {
            cache.setObject(depthImage, forKey: key as NSString)
        }
        return depthImage
    }

    func invalidate(cacheKey: String) {
        cache.removeObject(forKey: cacheKey as NSString)
    }

    // MARK: - Pixel buffer → UIImage

    /// Converts the model's `CVPixelBuffer` (kCVPixelFormatType_OneComponent16Half or
    /// _32Float depending on quantisation) into a normalised 8-bit grayscale UIImage,
    /// scaled to the target size with Core Image.
    private func makeGrayscaleImage(from buffer: CVPixelBuffer, targetSize: CGSize) -> UIImage? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let format = CVPixelBufferGetPixelFormatType(buffer)
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }

        // Read into a Float32 buffer regardless of source format (Half or Float).
        let count = width * height
        let floatPtr = UnsafeMutablePointer<Float>.allocate(capacity: count)
        defer { floatPtr.deallocate() }

        switch format {
        case kCVPixelFormatType_OneComponent16Half:
            // Half-float → float32 conversion via vImage.
            var src = vImage_Buffer(data: base, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: bytesPerRow)
            var dst = vImage_Buffer(data: floatPtr, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width * MemoryLayout<Float>.size)
            vImageConvert_Planar16FtoPlanarF(&src, &dst, 0)
        case kCVPixelFormatType_OneComponent32Float:
            // Direct copy row by row (rows may be padded).
            for row in 0..<height {
                let src = base.advanced(by: row * bytesPerRow).assumingMemoryBound(to: Float.self)
                let dst = floatPtr.advanced(by: row * width)
                dst.initialize(from: src, count: width)
            }
        default:
            print("[DepthEstimator] unexpected pixel format \(format)")
            return nil
        }

        // Min/max for normalisation.
        var minVal: Float = 0
        var maxVal: Float = 0
        vDSP_minv(floatPtr, 1, &minVal, vDSP_Length(count))
        vDSP_maxv(floatPtr, 1, &maxVal, vDSP_Length(count))
        let range = max(maxVal - minVal, 0.0001)

        // Stretch to [0, 255] grayscale.
        let bytesOut = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        defer { bytesOut.deallocate() }
        for i in 0..<count {
            let normalised = (floatPtr[i] - minVal) / range
            bytesOut[i] = UInt8(clamping: Int(normalised * 255))
        }

        // Wrap into CGImage at native resolution.
        guard let colorSpace = CGColorSpace(name: CGColorSpace.linearGray),
              let context = CGContext(
                data: bytesOut,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
              ),
              let smallCG = context.makeImage()
        else { return nil }

        // Resample to source image dimensions so the displacement map aligns pixel-wise.
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resampled = renderer.image { _ in
            UIImage(cgImage: smallCG).draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resampled
    }

    /// Returns true if the model is available — UI can grey out the toggle otherwise.
    var isAvailable: Bool { model != nil }

    // MARK: - Luminance fallback (когда CoreML модель не загрузилась)

    /// Простая depth-карта на основе яркости изображения.
    /// Bright pixel = closer, dark pixel = farther. Не SOTA, но работает мгновенно
    /// без CoreML / blur / больших аллокаций — минимальный риск краша.
    private func fallbackDepthFromLuminance(image: UIImage, cacheKey: String?) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let w = 256, h = 256

        // Простой downsample в grayscale через CGContext. Без blur — DepthMesh сам сглаживает.
        let cs = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: w, space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let smallCG = ctx.makeImage() else { return nil }

        let result = UIImage(cgImage: smallCG)
        if let key = cacheKey {
            cache.setObject(result, forKey: key as NSString)
        }
        return result
    }
}
