import Foundation
import UIKit
import SceneKit
import simd

/// Point cloud renderer для картин: каждый пиксель back-project в 3D-точку через depth-карту,
/// получаем splat-like volumetric визуализацию. Альтернатива tessellated mesh-у — даёт
/// "вокселький" эффект, где видно настоящую глубину пиксель-в-пиксель.
///
/// На A13 Neural Engine + GPU: 130k точек рендерятся 30-60 fps без проблем.
enum PointCloudBuilder {

    private static let cache = NSCache<NSString, SCNGeometry>()

    static func build(
        image: UIImage,
        depthMap: UIImage,
        width: CGFloat,
        height: CGFloat,
        reliefScale: Float,
        resolution: Int,
        pointSize: Float = 14.0,
        cacheKey: String? = nil
    ) -> SCNGeometry? {
        if let key = cacheKey, let cached = cache.object(forKey: ("pc_" + key) as NSString) {
            return cached
        }

        guard let depths = sampleGrayscale(image: depthMap, size: resolution),
              let colors = sampleRGB(image: image, size: resolution) else { return nil }

        let n = resolution
        let halfW = Float(width) / 2
        let halfH = Float(height) / 2
        let step = Float(1) / Float(n - 1)

        var positions: [SIMD3<Float>] = []
        var rgbColors: [SIMD3<Float>] = []
        positions.reserveCapacity(n * n)
        rgbColors.reserveCapacity(n * n)

        for j in 0..<n {
            let v = Float(j) * step
            let py = halfH - v * Float(height)
            for i in 0..<n {
                let u = Float(i) * step
                let px = -halfW + u * Float(width)
                let d = depths[j * n + i]
                let pz = (d - 0.5) * reliefScale
                positions.append(SIMD3<Float>(px, py, pz))

                let cIdx = (j * n + i) * 3
                rgbColors.append(SIMD3<Float>(colors[cIdx], colors[cIdx + 1], colors[cIdx + 2]))
            }
        }

        let posData = Data(bytes: positions, count: positions.count * MemoryLayout<SIMD3<Float>>.stride)
        let posSource = SCNGeometrySource(
            data: posData,
            semantic: .vertex,
            vectorCount: positions.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride
        )

        let colorData = Data(bytes: rgbColors, count: rgbColors.count * MemoryLayout<SIMD3<Float>>.stride)
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: rgbColors.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride
        )

        // Indices для точек — каждая вершина = один index
        var indices = [UInt32](repeating: 0, count: positions.count)
        for i in 0..<positions.count { indices[i] = UInt32(i) }
        let idxData = Data(bytes: indices, count: indices.count * MemoryLayout<UInt32>.size)
        let element = SCNGeometryElement(
            data: idxData,
            primitiveType: .point,
            primitiveCount: positions.count,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        // Размер точки в пикселях (на устройстве у которого retina × 2-3 даст крупные splat-ы)
        element.pointSize = CGFloat(pointSize)
        element.minimumPointScreenSpaceRadius = 1.0
        element.maximumPointScreenSpaceRadius = CGFloat(pointSize)

        let geometry = SCNGeometry(sources: [posSource, colorSource], elements: [element])

        // Material: vertex color → diffuse, без освещения (чтобы цвета не искажались)
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.isLitPerPixel = false
        mat.writesToDepthBuffer = true
        // SceneKit использует vertex color автоматически если material.diffuse не задан явно
        geometry.materials = [mat]

        if let key = cacheKey {
            cache.setObject(geometry, forKey: ("pc_" + key) as NSString)
        }
        return geometry
    }

    // MARK: - Sampling

    private static func sampleGrayscale(image: UIImage, size n: Int) -> [Float]? {
        guard let cg = image.cgImage else { return nil }
        let cs = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: n * n)
        guard let ctx = CGContext(
            data: &pixels, width: n, height: n, bitsPerComponent: 8,
            bytesPerRow: n, space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
        var out = [Float](repeating: 0, count: n * n)
        for j in 0..<n {
            let src = n - 1 - j
            for i in 0..<n {
                out[j * n + i] = Float(pixels[src * n + i]) / 255.0
            }
        }
        return out
    }

    private static func sampleRGB(image: UIImage, size n: Int) -> [Float]? {
        guard let cg = image.cgImage else { return nil }
        let cs = CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        guard let ctx = CGContext(
            data: &pixels, width: n, height: n, bitsPerComponent: 8,
            bytesPerRow: n * 4, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
        var out = [Float](repeating: 0, count: n * n * 3)
        for j in 0..<n {
            let src = n - 1 - j
            for i in 0..<n {
                let s = (src * n + i) * 4
                let d = (j * n + i) * 3
                out[d]     = Float(pixels[s])     / 255.0
                out[d + 1] = Float(pixels[s + 1]) / 255.0
                out[d + 2] = Float(pixels[s + 2]) / 255.0
            }
        }
        return out
    }

    static func invalidate(cacheKey: String) {
        cache.removeObject(forKey: ("pc_" + cacheKey) as NSString)
    }
}
