import Foundation
import UIKit
import SceneKit
import simd
import Accelerate

/// Строит **реальную 3D-геометрию** из depth-карты — заменяет плоский SCNPlane + displacement.
/// Каждая вершина физически смещена по depth, нормали вычислены из geometry → при вращении
/// видны настоящие выпуклости/впадины, а не только тени от normal map.
///
/// Использование:
/// ```
/// let mesh = DepthMesh.build(
///     depthMap: depthImage,      // grayscale из DepthEstimator
///     width: 2.0, height: 2.0,   // физические размеры плоскости в метрах
///     reliefScale: 0.18,         // максимальная глубина рельефа (м)
///     resolution: 256            // вершин по каждой стороне
/// )
/// let node = SCNNode(geometry: mesh)
/// node.geometry?.firstMaterial?.diffuse.contents = artworkImage
/// ```
enum DepthMesh {

    /// Кэш геометрии по cacheKey — пересчёт занимает 50-100 мс на 256×256, кэш экономит на повторных открытиях.
    private static let cache = NSCache<NSString, SCNGeometry>()

    static func build(
        depthMap: UIImage,
        width: CGFloat,
        height: CGFloat,
        reliefScale: Float,
        resolution: Int,
        cacheKey: String? = nil
    ) -> SCNGeometry? {
        if let key = cacheKey, let cached = cache.object(forKey: key as NSString) {
            return cached
        }

        guard let depthBytes = sampleDepth(image: depthMap, resolution: resolution) else { return nil }

        let n = resolution
        let halfW = Float(width) / 2
        let halfH = Float(height) / 2
        let step = Float(1) / Float(n - 1)

        // Vertex positions (n × n штук). Z берётся из depth.
        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity(n * n)
        for j in 0..<n {
            let v = Float(j) * step       // 0..1 along height
            let py = halfH - v * Float(height) // верх плоскости — y=+halfH
            for i in 0..<n {
                let u = Float(i) * step
                let px = -halfW + u * Float(width)
                // depth[i,j] = 0..1 (bright = near). reliefScale контролирует амплитуду
                let d = depthBytes[j * n + i]
                let pz = (d - 0.5) * reliefScale // центрируем — фон уходит назад, выпуклости вперёд
                positions.append(SIMD3<Float>(px, py, pz))
            }
        }

        // Normals — cross-product соседних edge-векторов
        var normals: [SIMD3<Float>] = Array(repeating: SIMD3<Float>(0, 0, 1), count: n * n)
        for j in 0..<n {
            for i in 0..<n {
                let i0 = max(i - 1, 0)
                let i1 = min(i + 1, n - 1)
                let j0 = max(j - 1, 0)
                let j1 = min(j + 1, n - 1)
                let dx = positions[j * n + i1] - positions[j * n + i0]
                let dy = positions[j1 * n + i] - positions[j0 * n + i]
                let nrm = simd_normalize(simd_cross(dx, dy))
                // Для нашей ориентации мы хотим нормаль смотрящую "наружу" (z+)
                normals[j * n + i] = nrm.z >= 0 ? nrm : -nrm
            }
        }

        // UV coords (одинаковые для diffuse и нормал-map)
        var uvs: [SIMD2<Float>] = []
        uvs.reserveCapacity(n * n)
        for j in 0..<n {
            for i in 0..<n {
                uvs.append(SIMD2<Float>(Float(i) * step, Float(j) * step))
            }
        }

        // Triangle indices — 2 треугольника на каждый quad
        var indices: [UInt32] = []
        indices.reserveCapacity((n - 1) * (n - 1) * 6)
        for j in 0..<(n - 1) {
            for i in 0..<(n - 1) {
                let a = UInt32(j * n + i)
                let b = UInt32(j * n + i + 1)
                let c = UInt32((j + 1) * n + i)
                let d = UInt32((j + 1) * n + i + 1)
                // Триплеты по CCW. Реверсим — у нас плоскость смотрит в +Z, тут CW для нужного facing.
                indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }

        // Создаём sources
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

        let normalData = Data(bytes: normals, count: normals.count * MemoryLayout<SIMD3<Float>>.stride)
        let normalSource = SCNGeometrySource(
            data: normalData,
            semantic: .normal,
            vectorCount: normals.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride
        )

        let uvData = Data(bytes: uvs, count: uvs.count * MemoryLayout<SIMD2<Float>>.stride)
        let uvSource = SCNGeometrySource(
            data: uvData,
            semantic: .texcoord,
            vectorCount: uvs.count,
            usesFloatComponents: true,
            componentsPerVector: 2,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD2<Float>>.stride
        )

        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<UInt32>.size)
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: indices.count / 3,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )

        let geometry = SCNGeometry(sources: [posSource, normalSource, uvSource], elements: [element])

        if let key = cacheKey {
            cache.setObject(geometry, forKey: key as NSString)
        }
        return geometry
    }

    /// Сэмплит depth-карту до n×n float-массива в [0..1] (1 = ближе к камере).
    private static func sampleDepth(image: UIImage, resolution n: Int) -> [Float]? {
        guard let cg = image.cgImage else { return nil }

        // Рендерим в greyscale n×n буфер
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bytesPerRow = n
        var pixels = [UInt8](repeating: 0, count: n * n)
        guard let ctx = CGContext(
            data: &pixels,
            width: n,
            height: n,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))

        // Нормализуем в [0..1] и переворачиваем по Y (CGContext рисует с инверсией)
        var out = [Float](repeating: 0, count: n * n)
        for j in 0..<n {
            let srcRow = n - 1 - j
            for i in 0..<n {
                out[j * n + i] = Float(pixels[srcRow * n + i]) / 255.0
            }
        }
        return out
    }

    static func invalidate(cacheKey: String) {
        cache.removeObject(forKey: cacheKey as NSString)
    }
}
