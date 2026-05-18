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
        // The CoreML compiler bakes `.mlpackage` resources into `.mlmodelc` bundles
        // inside the app at build time, so we look up the compiled form by name.
        guard let url = Bundle.main.url(forResource: "DepthAnythingV2SmallF16INT8", withExtension: "mlmodelc") else {
            print("[DepthEstimator] model bundle not found — falling back to nil")
            self.model = nil
            return
        }
        do {
            let mlConfig = MLModelConfiguration()
            // .all = let the OS pick CPU / GPU / Neural Engine per layer.
            mlConfig.computeUnits = .all
            let ml = try MLModel(contentsOf: url, configuration: mlConfig)
            self.model = try VNCoreMLModel(for: ml)
        } catch {
            print("[DepthEstimator] failed to load model: \(error)")
            self.model = nil
        }
    }

    /// Generates a single-channel depth map for `image`. The returned UIImage is grayscale,
    /// same dimensions as the input, encoded so that **bright pixels = nearer the camera**.
    /// Suitable for use as a displacement map: brighter = pushed out, darker = recessed.
    func depthMap(for image: UIImage, cacheKey: String? = nil) -> UIImage? {
        if let key = cacheKey, let cached = cache.object(forKey: key as NSString) {
            return cached
        }
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
}
