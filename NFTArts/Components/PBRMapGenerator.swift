import Foundation
import UIKit
import Accelerate

/// Дополнительные PBR-карты для tessellated mesh-картины:
/// - AO (ambient occlusion) — затемнение углублений по depth-карте (псевдо-AO через blur-difference)
/// - Roughness — более шероховато там где темнее текстура (стандартная heuristic для масляной живописи)
///
/// Использование: `PBRMapGenerator.generateAO(from: depth)` после Depth Anything V2.
enum PBRMapGenerator {

    private static let cache = NSCache<NSString, UIImage>()

    /// AO map из depth-карты: участки которые "ниже" окружающего среднего — более затемнены.
    /// Алгоритм: blur(depth) - depth → положительные значения = впадина → темнее.
    static func generateAO(fromDepth depth: UIImage, intensity: Float = 1.5, cacheKey: String? = nil) -> UIImage? {
        if let key = cacheKey, let cached = cache.object(forKey: "ao_\(key)" as NSString) {
            return cached
        }
        guard let cg = depth.cgImage else { return nil }
        let w = cg.width, h = cg.height

        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: w, space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Конвертируем в Float buffer
        var src = [Float](repeating: 0, count: w * h)
        for i in 0..<(w * h) { src[i] = Float(pixels[i]) / 255.0 }

        // Box blur 15×15 — даёт "среднее окружение" для каждой точки
        var blurred = src
        let radius = 7
        boxBlur(src: src, dst: &blurred, width: w, height: h, radius: radius)

        // AO = saturate( (blurred - src) * intensity ) — положительная разница = углубление
        var ao = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            let diff = (blurred[i] - src[i]) * intensity
            let occlusion = max(0, min(1, diff))
            // Финальный AO: 1.0 для плоскости, 1-occlusion для углублений (умножается на base albedo)
            let v = max(0, 1.0 - occlusion)
            ao[i] = UInt8(v * 255)
        }

        let result = grayscaleImage(from: ao, width: w, height: h)
        if let key = cacheKey, let r = result {
            cache.setObject(r, forKey: "ao_\(key)" as NSString)
        }
        return result
    }

    /// Roughness map из original image: яркие участки (блики) более глянцевые, тёмные — шероховатые.
    /// Полезно для масляной живописи где мазки = matte, чистый фон = глянец лака.
    static func generateRoughness(from image: UIImage, cacheKey: String? = nil) -> UIImage? {
        if let key = cacheKey, let cached = cache.object(forKey: "rough_\(key)" as NSString) {
            return cached
        }
        guard let cg = image.cgImage else { return nil }
        let w = cg.width, h = cg.height

        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: w, space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Инвертируем: dark pixels = высокая roughness, bright = низкая
        var rough = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            let luma = Float(pixels[i]) / 255.0
            // Mapping: luma=0 → roughness=0.85 (диффузно), luma=1 → roughness=0.25 (блестит)
            let r = 0.85 - 0.6 * luma
            rough[i] = UInt8(r * 255)
        }

        let result = grayscaleImage(from: rough, width: w, height: h)
        if let key = cacheKey, let r = result {
            cache.setObject(r, forKey: "rough_\(key)" as NSString)
        }
        return result
    }

    // MARK: - Helpers

    /// Separable box blur: сначала горизонтальный, потом вертикальный проход.
    /// O(width*height) — быстрее чем naive O(width*height*kernel^2).
    private static func boxBlur(src: [Float], dst: inout [Float], width: Int, height: Int, radius: Int) {
        var tmp = [Float](repeating: 0, count: width * height)
        // Horizontal pass — для каждого ряда считаем running sum
        let kernelSize = Float(2 * radius + 1)
        for y in 0..<height {
            let row = y * width
            for x in 0..<width {
                var sum: Float = 0
                let x0 = max(x - radius, 0)
                let x1 = min(x + radius, width - 1)
                for xi in x0...x1 { sum += src[row + xi] }
                tmp[row + x] = sum / kernelSize
            }
        }
        // Vertical pass
        for x in 0..<width {
            for y in 0..<height {
                var sum: Float = 0
                let y0 = max(y - radius, 0)
                let y1 = min(y + radius, height - 1)
                for yi in y0...y1 { sum += tmp[yi * width + x] }
                dst[y * width + x] = sum / kernelSize
            }
        }
    }

    private static func grayscaleImage(from bytes: [UInt8], width: Int, height: Int) -> UIImage? {
        let provider = CGDataProvider(data: Data(bytes) as CFData)
        guard let provider = provider else { return nil }
        let cs = CGColorSpaceCreateDeviceGray()
        guard let cg = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
            bytesPerRow: width, space: cs,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        ) else { return nil }
        return UIImage(cgImage: cg)
    }
}
