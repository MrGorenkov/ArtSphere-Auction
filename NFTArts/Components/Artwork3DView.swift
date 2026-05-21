import SwiftUI
import SceneKit

struct Artwork3DView: UIViewRepresentable {
    let artwork: NFTArtwork
    var artworkImage: UIImage?
    var allowsInteraction: Bool = true
    var showComplexityOverlay: Bool = false
    /// 0 = pure original, 1 = pure heatmap. Slider in the parent view rides this.
    var heatmapBlend: Double = 0.6
    /// Which 3D-relief pipeline to use. Defaults to the global default (currently `.hybrid`).
    var algorithm: NormalMapGenerator.FilterAlgorithm = NormalMapGenerator.defaultAlgorithm

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .clear
        scnView.antialiasingMode = .multisampling4X
        scnView.autoenablesDefaultLighting = false

        let scene = createScene(coordinator: context.coordinator)
        scnView.scene = scene
        context.coordinator.scene = scene
        context.coordinator.currentAlgorithm = algorithm

        if allowsInteraction {
            scnView.allowsCameraControl = true
            scnView.defaultCameraController.interactionMode = .orbitTurntable
            scnView.defaultCameraController.maximumVerticalAngle = 45
            scnView.defaultCameraController.minimumVerticalAngle = -45
        }

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.setComplexityOverlay(showComplexityOverlay, blend: heatmapBlend)
        if context.coordinator.currentAlgorithm != algorithm {
            context.coordinator.applyAlgorithm(algorithm, artwork: artwork)
        }
    }

    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) {
        coordinator.stopAnimations()
        uiView.scene = nil
        coordinator.scene = nil
    }

    // MARK: - Scene Creation

    private func createScene(coordinator: Coordinator) -> SCNScene {
        let sceneStart = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = (CFAbsoluteTimeGetCurrent() - sceneStart) * 1000
            MetricsService.shared.record(category: "3d_rendering", name: "scene_setup_ms", value: elapsed, unit: "ms",
                                         metadata: ["artwork": artwork.title])
        }
        let scene = SCNScene()

        // Resolve the image — synchronous (cached/bundled/local) or placeholder.
        // URL-based artworks render with the procedural placeholder first; the real image
        // is fetched on a background queue below and swapped in via the coordinator.
        let sourceImage = artworkImage ?? ImageLoader.cachedOrPlaceholder(for: artwork)

        let cacheKey = artwork.id.uuidString
        let normalMap = NormalMapGenerator.generate(from: sourceImage, cacheKey: cacheKey, algorithm: algorithm)

        // Calculate and record texture complexity metric for scientific analysis
        if let complexity = NormalMapGenerator.calculateTextureMetric(from: sourceImage) {
            MetricsService.shared.record(
                category: "image_analysis", name: "texture_complexity",
                value: complexity, unit: "ratio",
                metadata: ["artwork": artwork.title]
            )
        }

        // Store images in coordinator for overlay toggling
        coordinator.originalImage = sourceImage
        // Heatmap генерируется только когда юзер включит overlay — лениво,
        // чтобы не блокировать первый показ сцены (генерация ~1-3 сек на iPhone 11 Pro).
        Task.detached(priority: .utility) {
            let heatmap = NormalMapGenerator.generateComplexityHeatmap(from: sourceImage, cacheKey: cacheKey)
            await MainActor.run { coordinator.heatmapImage = heatmap }
        }

        // Parent node for grouped animation
        let parentNode = SCNNode()
        parentNode.name = "artworkGroup"
        scene.rootNode.addChildNode(parentNode)

        // Geometry: для Hybrid строим настоящую 3D-мешу из depth-карты (вершины физически
        // смещены — видно при любом ракурсе). Для Sobel/Laplacian остаётся быстрый
        // SCNPlane с displacement (мгновенное открытие).
        let heightMap = NormalMapGenerator.generateHeightmap(from: sourceImage, cacheKey: cacheKey, algorithm: algorithm)

        let material = SCNMaterial()
        material.diffuse.contents = sourceImage
        material.normal.contents = normalMap
        material.normal.intensity = 1.5
        material.roughness.contents = 0.45
        material.metalness.contents = 0.03
        material.lightingModel = .physicallyBased
        material.isDoubleSided = true

        let artworkGeometry: SCNGeometry
        if algorithm == .pointCloud {
            let depth = DepthEstimator.shared.depthMap(for: sourceImage, cacheKey: cacheKey)
            print("[3D] pointCloud build: depth=\(depth != nil ? "OK" : "nil")")
            if let depth = depth,
               let cloud = PointCloudBuilder.build(
                   image: sourceImage, depthMap: depth,
                   width: 2.0, height: 2.0, reliefScale: 0.28,
                   resolution: 360, pointSize: 12, cacheKey: cacheKey
               ) {
                print("[3D] pointCloud OK")
                artworkGeometry = cloud
            } else {
                print("[3D] pointCloud FAILED — fallback to plane")
                let plane = SCNPlane(width: 2.0, height: 2.0)
                plane.widthSegmentCount = 64; plane.heightSegmentCount = 64
                plane.materials = [material]
                artworkGeometry = plane
            }
        } else if algorithm == .hybrid,
           let depth = DepthEstimator.shared.depthMap(for: sourceImage, cacheKey: cacheKey),
           let mesh = DepthMesh.build(
               depthMap: depth,
               width: 2.0, height: 2.0,
               reliefScale: 0.22,
               resolution: 256,
               cacheKey: cacheKey
           ) {
            print("[3D] hybrid mesh OK")
            // PBR-усиление для Hybrid режима: тени в углублениях + per-pixel roughness
            if let ao = PBRMapGenerator.generateAO(fromDepth: depth, cacheKey: cacheKey) {
                material.ambientOcclusion.contents = ao
                material.ambientOcclusion.intensity = 1.0
            }
            if let rough = PBRMapGenerator.generateRoughness(from: sourceImage, cacheKey: cacheKey) {
                material.roughness.contents = rough
            }
            // Tessellated mesh — displacement не нужен, рельеф уже в вершинах
            mesh.materials = [material]
            artworkGeometry = mesh
        } else {
            if algorithm == .hybrid {
                print("[3D] hybrid FAILED — depth or mesh nil, fallback to plane")
            }
            let planeGeometry = SCNPlane(width: 2.0, height: 2.0)
            planeGeometry.cornerRadius = 0.05
            planeGeometry.widthSegmentCount = 64
            planeGeometry.heightSegmentCount = 64
            material.displacement.contents = heightMap
            material.displacement.intensity = 0.015
            planeGeometry.materials = [material]
            artworkGeometry = planeGeometry
        }

        let artworkNode = SCNNode(geometry: artworkGeometry)
        artworkNode.name = "artwork"
        parentNode.addChildNode(artworkNode)

        // Store reference for material/geometry switching
        coordinator.artworkMaterial = material
        coordinator.artworkNode = artworkNode

        // For URL-sourced artworks the placeholder may be a procedural fallback.
        // Upgrade to the real bytes in the background; swap on the main thread.
        if artworkImage == nil && artwork.imageSource == .url {
            let artId = artwork.id
            let snapshot = artwork
            let activeAlgorithm = algorithm
            Task.detached(priority: .userInitiated) {
                let loaded = await ImageLoader.loadImage(for: snapshot)
                // Drop placeholder-derived caches так чтобы Hybrid/Splat пересчитались с реального изображения.
                NormalMapGenerator.invalidate(cacheKey: artId.uuidString)
                DepthMesh.invalidate(cacheKey: artId.uuidString)
                PointCloudBuilder.invalidate(cacheKey: artId.uuidString)
                let newNormal = NormalMapGenerator.generate(from: loaded, cacheKey: artId.uuidString, algorithm: activeAlgorithm)
                let newHeight = NormalMapGenerator.generateHeightmap(from: loaded, cacheKey: artId.uuidString, algorithm: activeAlgorithm)
                let newHeatmap = NormalMapGenerator.generateComplexityHeatmap(from: loaded, cacheKey: artId.uuidString)

                // Для Hybrid и Splat нужно пересчитать саму геометрию по реальной картинке
                var rebuiltGeometry: SCNGeometry?
                if activeAlgorithm == .hybrid,
                   let depth = DepthEstimator.shared.depthMap(for: loaded, cacheKey: artId.uuidString),
                   let mesh = DepthMesh.build(
                       depthMap: depth, width: 2.0, height: 2.0,
                       reliefScale: 0.22, resolution: 256, cacheKey: artId.uuidString) {
                    mesh.materials = [material]
                    rebuiltGeometry = mesh
                } else if activeAlgorithm == .pointCloud,
                   let depth = DepthEstimator.shared.depthMap(for: loaded, cacheKey: artId.uuidString),
                   let cloud = PointCloudBuilder.build(
                       image: loaded, depthMap: depth,
                       width: 2.0, height: 2.0, reliefScale: 0.28,
                       resolution: 360, pointSize: 12, cacheKey: artId.uuidString) {
                    rebuiltGeometry = cloud
                }

                await MainActor.run {
                    coordinator.originalImage = loaded
                    coordinator.heatmapImage = newHeatmap
                    material.diffuse.contents = loaded
                    material.normal.contents = newNormal
                    if activeAlgorithm == .hybrid {
                        material.displacement.contents = nil
                        material.displacement.intensity = 0
                    } else if activeAlgorithm != .pointCloud {
                        material.displacement.contents = newHeight
                    }
                    if let g = rebuiltGeometry {
                        coordinator.artworkNode?.geometry = g
                    }
                }
            }
        }

        // Frame (4 separate bars for realistic look)
        let frameThickness: CGFloat = 0.08
        let frameDepth: CGFloat = 0.12
        let innerW: CGFloat = 2.0
        let innerH: CGFloat = 2.0

        let frameMat = SCNMaterial()
        frameMat.diffuse.contents = UIColor(white: 0.12, alpha: 1.0)
        frameMat.roughness.contents = 0.25
        frameMat.metalness.contents = 0.85
        frameMat.lightingModel = .physicallyBased

        // Top
        let topBar = SCNBox(width: innerW + frameThickness * 2, height: frameThickness, length: frameDepth, chamferRadius: 0.01)
        topBar.materials = [frameMat]
        let topNode = SCNNode(geometry: topBar)
        topNode.position = SCNVector3(0, Float(innerH / 2 + frameThickness / 2), Float(-frameDepth / 2 + 0.01))
        parentNode.addChildNode(topNode)

        // Bottom
        let bottomBar = SCNBox(width: innerW + frameThickness * 2, height: frameThickness, length: frameDepth, chamferRadius: 0.01)
        bottomBar.materials = [frameMat]
        let bottomNode = SCNNode(geometry: bottomBar)
        bottomNode.position = SCNVector3(0, Float(-innerH / 2 - frameThickness / 2), Float(-frameDepth / 2 + 0.01))
        parentNode.addChildNode(bottomNode)

        // Left
        let leftBar = SCNBox(width: frameThickness, height: innerH, length: frameDepth, chamferRadius: 0.01)
        leftBar.materials = [frameMat]
        let leftNode = SCNNode(geometry: leftBar)
        leftNode.position = SCNVector3(Float(-innerW / 2 - frameThickness / 2), 0, Float(-frameDepth / 2 + 0.01))
        parentNode.addChildNode(leftNode)

        // Right
        let rightBar = SCNBox(width: frameThickness, height: innerH, length: frameDepth, chamferRadius: 0.01)
        rightBar.materials = [frameMat]
        let rightNode = SCNNode(geometry: rightBar)
        rightNode.position = SCNVector3(Float(innerW / 2 + frameThickness / 2), 0, Float(-frameDepth / 2 + 0.01))
        parentNode.addChildNode(rightNode)

        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 40
        cameraNode.camera?.zNear = 0.1
        cameraNode.camera?.zFar = 100
        cameraNode.position = SCNVector3(0, 0, 4.5)
        cameraNode.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(cameraNode)

        addLighting(to: scene)

        // Gentle oscillation instead of full rotation (prevents edge-on disappearing)
        let oscillateY = SCNAction.sequence([
            SCNAction.rotateBy(x: 0, y: 0.15, z: 0, duration: 3.0),
            SCNAction.rotateBy(x: 0, y: -0.30, z: 0, duration: 6.0),
            SCNAction.rotateBy(x: 0, y: 0.15, z: 0, duration: 3.0)
        ])
        let oscillateX = SCNAction.sequence([
            SCNAction.rotateBy(x: 0.05, y: 0, z: 0, duration: 4.0),
            SCNAction.rotateBy(x: -0.10, y: 0, z: 0, duration: 8.0),
            SCNAction.rotateBy(x: 0.05, y: 0, z: 0, duration: 4.0)
        ])
        let oscillateYKey = "oscillateY"
        let oscillateXKey = "oscillateX"
        parentNode.runAction(.repeatForever(oscillateY), forKey: oscillateYKey)
        parentNode.runAction(.repeatForever(oscillateX), forKey: oscillateXKey)

        coordinator.animationKeys = [oscillateYKey, oscillateXKey]

        return scene
    }

    private func addLighting(to scene: SCNScene) {
        let keyLight = SCNNode()
        keyLight.light = SCNLight()
        keyLight.light?.type = .directional
        keyLight.light?.intensity = 900
        keyLight.light?.color = UIColor.white
        keyLight.light?.castsShadow = true
        keyLight.light?.shadowRadius = 8
        keyLight.position = SCNVector3(2, 3, 5)
        keyLight.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(keyLight)

        let fillLight = SCNNode()
        fillLight.light = SCNLight()
        fillLight.light?.type = .directional
        fillLight.light?.intensity = 350
        fillLight.light?.color = UIColor(red: 0.8, green: 0.85, blue: 1.0, alpha: 1.0)
        fillLight.position = SCNVector3(-3, 1, 3)
        fillLight.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(fillLight)

        let rimLight = SCNNode()
        rimLight.light = SCNLight()
        rimLight.light?.type = .directional
        rimLight.light?.intensity = 250
        rimLight.light?.color = UIColor(red: 0.7, green: 0.7, blue: 1.0, alpha: 1.0)
        rimLight.position = SCNVector3(0, -1, -3)
        rimLight.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(rimLight)

        // Raking light — low-angle light to catch brushstroke texture edges
        let rakingLight = SCNNode()
        rakingLight.light = SCNLight()
        rakingLight.light?.type = .directional
        rakingLight.light?.intensity = 200
        rakingLight.light?.color = UIColor(white: 0.9, alpha: 1.0)
        rakingLight.position = SCNVector3(5, 0.3, 2)
        rakingLight.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(rakingLight)

        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 250
        ambientLight.light?.color = UIColor(white: 0.7, alpha: 1.0)
        scene.rootNode.addChildNode(ambientLight)
    }

    class Coordinator {
        weak var scene: SCNScene?
        weak var artworkNode: SCNNode?
        var artworkMaterial: SCNMaterial?
        var originalImage: UIImage?
        var heatmapImage: UIImage?
        var currentAlgorithm: NormalMapGenerator.FilterAlgorithm = NormalMapGenerator.defaultAlgorithm
        private var isShowingOverlay = false
        var animationKeys: [String] = []

        /// При смене алгоритма:
        /// - Sobel/Laplacian: меняем только maps на плоскости (мгновенно)
        /// - Hybrid: полностью пересоздаём геометрию из depth-карты (tessellated mesh)
        ///   и подменяем у ноды — переход видно как реальное "выдвижение" рельефа.
        func applyAlgorithm(_ new: NormalMapGenerator.FilterAlgorithm, artwork: NFTArtwork) {
            print("[3D] applyAlgorithm: prev=\(currentAlgorithm.rawValue) new=\(new.rawValue) material=\(artworkMaterial != nil) source=\(originalImage != nil) node=\(artworkNode != nil)")
            guard let material = artworkMaterial,
                  let source = originalImage,
                  let node = artworkNode else { return }
            let prev = currentAlgorithm
            currentAlgorithm = new
            let cacheKey = artwork.id.uuidString

            // СИНХРОННАЯ ВЕТКА для hybrid/pointCloud — нужна чтобы дебажить.
            // Async Task.detached внизу обрабатывает Sobel.
            if new == .hybrid {
                print("[3D] hybrid SYNC start")
                if let depth = DepthEstimator.shared.depthMap(for: source, cacheKey: cacheKey) {
                    print("[3D] hybrid depth OK size=\(depth.size)")
                    if let mesh = DepthMesh.build(depthMap: depth, width: 2.0, height: 2.0, reliefScale: 0.22, resolution: 128, cacheKey: cacheKey) {
                        print("[3D] hybrid mesh OK — applying to node")
                        material.displacement.contents = nil
                        material.displacement.intensity = 0
                        mesh.materials = [material]
                        node.geometry = mesh
                    } else {
                        print("[3D] hybrid mesh BUILD FAILED")
                    }
                } else {
                    print("[3D] hybrid depth NIL")
                }
                return
            }
            if new == .pointCloud {
                print("[3D] pointCloud SYNC start")
                if let depth = DepthEstimator.shared.depthMap(for: source, cacheKey: cacheKey),
                   let cloud = PointCloudBuilder.build(image: source, depthMap: depth, width: 2.0, height: 2.0, reliefScale: 0.28, resolution: 200, pointSize: 12, cacheKey: cacheKey) {
                    print("[3D] pointCloud OK — applying to node")
                    node.geometry = cloud
                } else {
                    print("[3D] pointCloud BUILD FAILED")
                }
                return
            }

            Task.detached(priority: .userInitiated) {
                print("[3D] Task started")
                let normalMap = NormalMapGenerator.generate(from: source, cacheKey: cacheKey, algorithm: new)
                print("[3D] normalMap done")
                let heightMap = NormalMapGenerator.generateHeightmap(from: source, cacheKey: cacheKey, algorithm: new)
                print("[3D] heightMap done, entering switch, new=\(new.rawValue) prev=\(prev.rawValue)")

                // Геометрия меняется по типу алгоритма: plane (Sobel/Laplacian),
                // tessellated mesh (Hybrid), point cloud (Splat).
                var newGeometry: SCNGeometry?
                if new != prev {
                    switch new {
                    case .hybrid:
                        let depth = DepthEstimator.shared.depthMap(for: source, cacheKey: cacheKey)
                        print("[3D] hybrid: depth=\(depth != nil ? "OK" : "NIL")")
                        if let depth = depth,
                           let mesh = DepthMesh.build(
                               depthMap: depth, width: 2.0, height: 2.0,
                               reliefScale: 0.22, resolution: 256, cacheKey: cacheKey) {
                            print("[3D] hybrid mesh: vertices count built")
                            if let ao = PBRMapGenerator.generateAO(fromDepth: depth, cacheKey: cacheKey) {
                                material.ambientOcclusion.contents = ao
                                material.ambientOcclusion.intensity = 1.0
                            }
                            if let rough = PBRMapGenerator.generateRoughness(from: source, cacheKey: cacheKey) {
                                material.roughness.contents = rough
                            }
                            mesh.materials = [material]
                            newGeometry = mesh
                        }
                    case .pointCloud:
                        let depth = DepthEstimator.shared.depthMap(for: source, cacheKey: cacheKey)
                        print("[3D] pointCloud: depth=\(depth != nil ? "OK" : "NIL")")
                        if let depth = depth,
                           let cloud = PointCloudBuilder.build(
                               image: source, depthMap: depth,
                               width: 2.0, height: 2.0, reliefScale: 0.28,
                               resolution: 360, pointSize: 12, cacheKey: cacheKey) {
                            print("[3D] pointCloud built")
                            newGeometry = cloud
                        }
                    case .sobel:
                        let plane = SCNPlane(width: 2.0, height: 2.0)
                        plane.cornerRadius = 0.05
                        plane.widthSegmentCount = 64
                        plane.heightSegmentCount = 64
                        material.ambientOcclusion.contents = nil
                        material.roughness.contents = 0.45
                        plane.materials = [material]
                        newGeometry = plane
                    }
                }

                await MainActor.run {
                    material.normal.contents = normalMap
                    if new == .hybrid {
                        // Mesh сам несёт рельеф — displacement выключаем чтобы не было двойного эффекта
                        material.displacement.contents = nil
                        material.displacement.intensity = 0.0
                    } else {
                        material.displacement.contents = heightMap
                        material.displacement.intensity = 0.015
                    }
                    if let g = newGeometry {
                        node.geometry = g
                    }
                }
            }
        }

        func stopAnimations() {
            if let scene = scene,
               let parent = scene.rootNode.childNode(withName: "artworkGroup", recursively: false) {
                for key in animationKeys {
                    parent.removeAction(forKey: key)
                }
            }
            animationKeys.removeAll()
        }

        private var lastBlend: Double = -1

        /// Drives the heatmap overlay. When `show` is true the diffuse texture becomes
        /// a per-pixel mix of original ↔ heatmap controlled by `blend` (0 = original,
        /// 1 = heatmap). Pre-blends the composite once per (show, blend) pair so the
        /// slider stays responsive.
        func setComplexityOverlay(_ show: Bool, blend: Double = 0.6) {
            guard let material = artworkMaterial else { return }
            let blendChanged = abs(blend - lastBlend) > 0.01
            if show == isShowingOverlay && !blendChanged && show == false {
                return
            }
            isShowingOverlay = show
            lastBlend = blend

            if show, let heatmap = heatmapImage, let original = originalImage {
                let composite = blendImages(base: original, overlay: heatmap, alpha: blend)
                material.diffuse.contents = composite
                // Keep the normal map active so 3D relief is preserved over the heatmap —
                // the commission asked for an overlay, not a flat replacement.
                material.normal.intensity = 0.6
                material.lightingModel = .lambert
            } else if let original = originalImage {
                material.diffuse.contents = original
                material.normal.intensity = 1.5
                material.lightingModel = .physicallyBased
            }
        }

        /// Per-pixel alpha blend of two same-sized images via Core Graphics. Cheap
        /// enough to run on every slider tick (~5 ms for a 1024×1024 image).
        private func blendImages(base: UIImage, overlay: UIImage, alpha: Double) -> UIImage {
            let renderer = UIGraphicsImageRenderer(size: base.size)
            return renderer.image { _ in
                base.draw(in: CGRect(origin: .zero, size: base.size))
                overlay.draw(in: CGRect(origin: .zero, size: base.size), blendMode: .normal, alpha: CGFloat(alpha))
            }
        }
    }
}
