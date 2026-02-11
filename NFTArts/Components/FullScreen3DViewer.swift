import SwiftUI
import SceneKit

/// Fullscreen 3D viewer with free orbit camera controls.
/// Supports loading USDZ from URL or generating a framed artwork from the image.
struct FullScreen3DViewer: View {
    let artwork: NFTArtwork
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var usdzScene: SCNScene?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let scene = usdzScene {
                SceneKitViewer(scene: scene)
                    .ignoresSafeArea()
            } else if !isLoading {
                InteractiveArtwork3DView(artwork: artwork)
                    .ignoresSafeArea()
            }

            // Loading overlay
            if isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
            }

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white.opacity(0.8))
                            .shadow(radius: 4)
                    }
                    .padding(20)
                }
                Spacer()
            }

            // Hint at bottom
            VStack {
                Spacer()
                Text(L10n.rotateToInspect)
                    .font(NFTTypography.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial.opacity(0.5))
                    .clipShape(Capsule())
                    .padding(.bottom, 40)
            }

            // Title overlay
            VStack {
                Spacer()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(artwork.title)
                            .font(NFTTypography.headline)
                            .foregroundStyle(.white)
                        Text(artwork.artistName)
                            .font(NFTTypography.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 80)
            }
        }
        .onAppear { loadModel() }
    }

    private func loadModel() {
        // Try loading USDZ from URL
        if let urlString = artwork.modelUrl, let url = URL(string: urlString) {
            Task {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    let tempDir = FileManager.default.temporaryDirectory
                    let fileUrl = tempDir.appendingPathComponent("\(artwork.id.uuidString).usdz")
                    try data.write(to: fileUrl)

                    let scene = try SCNScene(url: fileUrl)
                    await MainActor.run {
                        self.usdzScene = scene
                        self.isLoading = false
                    }
                } catch {
                    // Fall back to generated 3D
                    await MainActor.run { self.isLoading = false }
                }
            }
        } else {
            // No USDZ — use generated 3D artwork view
            isLoading = false
        }
    }
}

// MARK: - SceneKit Viewer (for USDZ scenes)

private struct SceneKitViewer: UIViewRepresentable {
    let scene: SCNScene

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = scene
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.backgroundColor = .black
        scnView.antialiasingMode = .multisampling4X
        scnView.defaultCameraController.interactionMode = .orbitTurntable
        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}

// MARK: - Interactive Artwork 3D View (orbit camera, no auto-rotate)

struct InteractiveArtwork3DView: UIViewRepresentable {
    let artwork: NFTArtwork

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .black
        scnView.antialiasingMode = .multisampling4X
        scnView.allowsCameraControl = true
        scnView.defaultCameraController.interactionMode = .orbitTurntable
        scnView.defaultCameraController.minimumVerticalAngle = -60
        scnView.defaultCameraController.maximumVerticalAngle = 60

        let scene = SCNScene()
        scnView.scene = scene

        // Create artwork node
        let artworkNode = createArtworkNode()
        scene.rootNode.addChildNode(artworkNode)

        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 50
        cameraNode.position = SCNVector3(0, 0, 3.5)
        scene.rootNode.addChildNode(cameraNode)
        scnView.pointOfView = cameraNode

        // Lighting
        addLighting(to: scene)

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    private func createArtworkNode() -> SCNNode {
        let parentNode = SCNNode()

        // Artwork surface
        let plane = SCNPlane(width: 2.0, height: 2.0)
        plane.widthSegmentCount = 48
        plane.heightSegmentCount = 48
        plane.cornerRadius = 0.05

        let material = SCNMaterial()
        material.lightingModel = .physicallyBased

        let image = loadArtworkImage()
        material.diffuse.contents = image

        if let img = image {
            let normalMap = NormalMapGenerator.generate(from: img)
            material.normal.contents = normalMap
            material.normal.intensity = 1.0
        }

        material.roughness.contents = NSNumber(value: 0.35)
        material.metalness.contents = NSNumber(value: 0.05)
        material.isDoubleSided = true

        plane.materials = [material]
        let artworkPlane = SCNNode(geometry: plane)
        parentNode.addChildNode(artworkPlane)

        // Frame
        addFrame(to: parentNode, width: 2.0, height: 2.0)

        // Back panel
        let backPlane = SCNPlane(width: 2.1, height: 2.1)
        let backMaterial = SCNMaterial()
        backMaterial.diffuse.contents = UIColor(white: 0.08, alpha: 1.0)
        backMaterial.lightingModel = .physicallyBased
        backMaterial.roughness.contents = NSNumber(value: 0.9)
        backPlane.materials = [backMaterial]
        let backNode = SCNNode(geometry: backPlane)
        backNode.position = SCNVector3(0, 0, -0.07)
        parentNode.addChildNode(backNode)

        return parentNode
    }

    private func loadArtworkImage() -> UIImage? {
        if artwork.imageSource == .uploaded, let data = artwork.localImageData {
            return UIImage(data: data)
        }
        if artwork.imageSource == .url, let urlString = artwork.imageURL {
            // Synchronous load for SceneKit texture
            if let url = URL(string: urlString),
               let data = try? Data(contentsOf: url) {
                return UIImage(data: data)
            }
        }
        return MockDataService.generateArtworkImage(
            for: artwork,
            size: CGSize(width: 512, height: 512)
        )
    }

    private func addFrame(to parent: SCNNode, width: CGFloat, height: CGFloat) {
        let thickness: CGFloat = 0.08
        let depth: CGFloat = 0.12

        let frameMaterial = SCNMaterial()
        frameMaterial.diffuse.contents = UIColor(white: 0.12, alpha: 1.0)
        frameMaterial.lightingModel = .physicallyBased
        frameMaterial.metalness.contents = NSNumber(value: 0.85)
        frameMaterial.roughness.contents = NSNumber(value: 0.25)

        let bars: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (width + thickness, thickness, depth, 0, height / 2 + thickness / 2),   // top
            (width + thickness, thickness, depth, 0, -(height / 2 + thickness / 2)), // bottom
            (thickness, height + thickness, depth, -(width / 2 + thickness / 2), 0), // left
            (thickness, height + thickness, depth, width / 2 + thickness / 2, 0),    // right
        ]

        for (w, h, d, x, y) in bars {
            let box = SCNBox(width: w, height: h, length: d, chamferRadius: 0.005)
            box.materials = [frameMaterial]
            let node = SCNNode(geometry: box)
            node.position = SCNVector3(x, y, 0)
            parent.addChildNode(node)
        }
    }

    private func addLighting(to scene: SCNScene) {
        let keyLight = SCNLight()
        keyLight.type = .directional
        keyLight.intensity = 900
        keyLight.castsShadow = true
        let keyNode = SCNNode()
        keyNode.light = keyLight
        keyNode.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 6, 0)
        scene.rootNode.addChildNode(keyNode)

        let fillLight = SCNLight()
        fillLight.type = .directional
        fillLight.intensity = 350
        fillLight.color = UIColor(red: 0.8, green: 0.85, blue: 1.0, alpha: 1.0)
        let fillNode = SCNNode()
        fillNode.light = fillLight
        fillNode.eulerAngles = SCNVector3(-Float.pi / 6, -Float.pi / 4, 0)
        scene.rootNode.addChildNode(fillNode)

        let rimLight = SCNLight()
        rimLight.type = .directional
        rimLight.intensity = 250
        let rimNode = SCNNode()
        rimNode.light = rimLight
        rimNode.eulerAngles = SCNVector3(Float.pi / 6, Float.pi, 0)
        scene.rootNode.addChildNode(rimNode)

        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.intensity = 250
        ambientLight.color = UIColor(white: 0.7, alpha: 1.0)
        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)
    }
}
