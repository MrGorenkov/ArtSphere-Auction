import SwiftUI
import SceneKit

struct Artwork3DView: UIViewRepresentable {
    let artwork: NFTArtwork
    var artworkImage: UIImage?
    var allowsInteraction: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .clear
        scnView.antialiasingMode = .multisampling4X
        scnView.autoenablesDefaultLighting = false

        let scene = createScene()
        scnView.scene = scene
        context.coordinator.scene = scene

        if allowsInteraction {
            scnView.allowsCameraControl = true
            scnView.defaultCameraController.interactionMode = .orbitTurntable
            scnView.defaultCameraController.maximumVerticalAngle = 45
            scnView.defaultCameraController.minimumVerticalAngle = -45
        }

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    // MARK: - Scene Creation

    private func createScene() -> SCNScene {
        let scene = SCNScene()

        // Resolve the image to use
        let sourceImage: UIImage
        if let img = artworkImage {
            sourceImage = img
        } else {
            sourceImage = MockDataService.generateArtworkImage(for: artwork, size: CGSize(width: 512, height: 512))
        }

        let normalMap = NormalMapGenerator.generate(from: sourceImage)

        // Parent node for grouped animation
        let parentNode = SCNNode()
        parentNode.name = "artworkGroup"
        scene.rootNode.addChildNode(parentNode)

        // Artwork plane with subdivision for depth effect
        let planeGeometry = SCNPlane(width: 2.0, height: 2.0)
        planeGeometry.cornerRadius = 0.05
        planeGeometry.widthSegmentCount = 48
        planeGeometry.heightSegmentCount = 48

        let material = SCNMaterial()
        material.diffuse.contents = sourceImage
        material.normal.contents = normalMap
        material.normal.intensity = 1.0
        material.roughness.contents = 0.35
        material.metalness.contents = 0.05
        material.lightingModel = .physicallyBased
        material.isDoubleSided = true
        planeGeometry.materials = [material]

        let artworkNode = SCNNode(geometry: planeGeometry)
        artworkNode.name = "artwork"
        parentNode.addChildNode(artworkNode)

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
        parentNode.runAction(.repeatForever(oscillateY))
        parentNode.runAction(.repeatForever(oscillateX))

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

        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 250
        ambientLight.light?.color = UIColor(white: 0.7, alpha: 1.0)
        scene.rootNode.addChildNode(ambientLight)
    }

    class Coordinator {
        var scene: SCNScene?
    }
}
