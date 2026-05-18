import Foundation
import SceneKit
import UIKit

/// Builds a 3D showroom scene: a square room with paintings hanging on the walls.
/// Each painting reuses the same PBR material (diffuse + normal map + displacement) as the
/// single-artwork viewer, so the visual style stays consistent across the app.
enum ShowroomSceneBuilder {

    // MARK: - Layout constants

    /// Side length of the square room in metres.
    private static let roomSize: Float = 12.0
    private static let roomHeight: Float = 4.5
    private static let wallThickness: Float = 0.15
    /// Height (in metres) at which the centre of every painting sits — eye level.
    private static let paintingCentreY: Float = 1.7
    /// Default painting size on the wall.
    private static let paintingSize: CGFloat = 1.6

    // MARK: - Scene assembly

    /// Builds a scene populated with up to 12 artworks. Empty walls are still rendered.
    /// Each painting is initially flat (diffuse only) so the room appears instantly;
    /// normal & height maps are computed lazily on a background queue and applied when ready.
    static func build(artworks: [NFTArtwork]) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor(red: 0.10, green: 0.08, blue: 0.06, alpha: 1.0)

        addFloor(to: scene)
        addCeiling(to: scene)
        addWalls(to: scene)
        addPaintings(to: scene, artworks: Array(artworks.prefix(12)))
        addLighting(to: scene)
        addDecor(to: scene)
        addCamera(to: scene)

        return scene
    }

    // MARK: - Floor & ceiling

    private static func addFloor(to scene: SCNScene) {
        // Wooden parquet plane — matte (no SCNFloor reflection per design feedback).
        let plane = SCNPlane(width: CGFloat(roomSize), height: CGFloat(roomSize))
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(red: 0.32, green: 0.22, blue: 0.14, alpha: 1.0) // warm walnut
        mat.diffuse.contentsTransform = SCNMatrix4MakeScale(6, 6, 1) // tile the implied parquet
        mat.diffuse.wrapS = .repeat
        mat.diffuse.wrapT = .repeat
        mat.roughness.contents = 0.85
        mat.metalness.contents = 0.0
        mat.lightingModel = .physicallyBased
        plane.materials = [mat]

        let node = SCNNode(geometry: plane)
        node.eulerAngles.x = -.pi / 2 // face up
        scene.rootNode.addChildNode(node)
    }

    private static func addCeiling(to scene: SCNScene) {
        let plane = SCNPlane(width: CGFloat(roomSize), height: CGFloat(roomSize))
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(red: 0.94, green: 0.92, blue: 0.86, alpha: 1.0) // ivory
        mat.lightingModel = .lambert
        mat.isDoubleSided = true
        plane.materials = [mat]

        let node = SCNNode(geometry: plane)
        node.position = SCNVector3(0, roomHeight, 0)
        node.eulerAngles.x = .pi / 2 // face down
        scene.rootNode.addChildNode(node)
    }

    // MARK: - Walls

    private static func addWalls(to scene: SCNScene) {
        // Warm gallery beige (Louvre-like sandstone tone).
        let wallMat = SCNMaterial()
        wallMat.diffuse.contents = UIColor(red: 0.78, green: 0.71, blue: 0.60, alpha: 1.0)
        wallMat.roughness.contents = 0.95
        wallMat.metalness.contents = 0.0
        wallMat.lightingModel = .physicallyBased

        // Dark wooden baseboard / chair-rail trim material.
        let trimMat = SCNMaterial()
        trimMat.diffuse.contents = UIColor(red: 0.20, green: 0.13, blue: 0.08, alpha: 1.0)
        trimMat.roughness.contents = 0.6
        trimMat.metalness.contents = 0.0
        trimMat.lightingModel = .physicallyBased

        for direction in WallDirection.allCases {
            // Main wall.
            let geometry = SCNBox(
                width: CGFloat(roomSize),
                height: CGFloat(roomHeight),
                length: CGFloat(wallThickness),
                chamferRadius: 0.0
            )
            geometry.materials = [wallMat]

            let node = SCNNode(geometry: geometry)
            node.position = direction.wallCentre(roomSize: roomSize, roomHeight: roomHeight, thickness: wallThickness)
            node.eulerAngles.y = direction.wallRotationY
            scene.rootNode.addChildNode(node)

            // Baseboard along the bottom (~12 cm tall, slightly forward from wall).
            let base = SCNBox(width: CGFloat(roomSize), height: 0.12, length: CGFloat(wallThickness * 1.3), chamferRadius: 0.005)
            base.materials = [trimMat]
            let baseNode = SCNNode(geometry: base)
            var basePos = node.position
            basePos.y = 0.06
            baseNode.position = basePos
            baseNode.eulerAngles.y = direction.wallRotationY
            scene.rootNode.addChildNode(baseNode)

            // Crown molding strip near the ceiling (~8 cm).
            let crown = SCNBox(width: CGFloat(roomSize), height: 0.08, length: CGFloat(wallThickness * 1.2), chamferRadius: 0.002)
            crown.materials = [trimMat]
            let crownNode = SCNNode(geometry: crown)
            var crownPos = node.position
            crownPos.y = roomHeight - 0.04
            crownNode.position = crownPos
            crownNode.eulerAngles.y = direction.wallRotationY
            scene.rootNode.addChildNode(crownNode)
        }
    }

    // MARK: - Paintings

    /// Distributes `artworks` evenly across the four walls (≤3 per wall).
    private static func addPaintings(to scene: SCNScene, artworks: [NFTArtwork]) {
        guard !artworks.isEmpty else { return }

        // Distribute artworks across 4 walls.
        let walls = WallDirection.allCases
        var perWall: [WallDirection: [NFTArtwork]] = [:]
        for (i, art) in artworks.enumerated() {
            let wall = walls[i % walls.count]
            perWall[wall, default: []].append(art)
        }

        for (direction, items) in perWall {
            place(artworks: items, on: direction, in: scene)
        }
    }

    private static func place(artworks: [NFTArtwork], on wall: WallDirection, in scene: SCNScene) {
        // Centre the row of paintings on the wall, with equal spacing.
        let count = artworks.count
        let totalSpan = Float(roomSize) * 0.75 // leave 12.5% margin on each side
        let step = count > 1 ? totalSpan / Float(count - 1) : 0
        let startOffset = count > 1 ? -totalSpan / 2 : 0

        // Walls where the observer's "right" axis runs opposite the world axis used for `alongWall`.
        // Without this flip, paintings on opposite walls appear in reversed visual order.
        let flipOrder: Bool
        switch wall {
        case .north, .east: flipOrder = false
        case .south, .west: flipOrder = true
        }

        for (i, artwork) in artworks.enumerated() {
            let visualIndex = flipOrder ? (count - 1 - i) : i
            let alongWall = startOffset + Float(visualIndex) * step
            let position = wall.paintingPosition(
                roomSize: roomSize,
                paintingY: paintingCentreY,
                alongWall: alongWall,
                wallThickness: wallThickness
            )
            let paintingNode = makePaintingNode(for: artwork)
            paintingNode.position = position
            paintingNode.eulerAngles.y = wall.paintingRotationY
            scene.rootNode.addChildNode(paintingNode)

            // Picture light: small warm spot mounted just above the frame, aimed at canvas centre.
            addPictureLight(at: position, wall: wall, in: scene)
        }
    }

    /// Museum-style "picture lamp": mounted above the frame, angled 30° down at the canvas.
    /// Wide enough cone (45°) to cover the whole 1.6 m painting evenly, no hard edge fall-off.
    /// Adds a small brass arm + lamp head as visible geometry above the frame.
    private static func addPictureLight(at paintingPos: SCNVector3, wall: WallDirection, in scene: SCNScene) {
        let lightNode = SCNNode()
        lightNode.name = "showroom_picture_light"
        let light = SCNLight()
        light.type = .spot
        // Whisper-soft accent — almost imperceptible warm glow on the canvas top.
        light.intensity = 25
        light.spotInnerAngle = 50
        light.spotOuterAngle = 90
        light.color = UIColor(red: 1.0, green: 0.93, blue: 0.78, alpha: 1.0) // warm halogen
        light.attenuationStartDistance = 0.5
        light.attenuationEndDistance = 3.5
        light.castsShadow = false // soft fill, shadowless to keep painting evenly lit
        lightNode.light = light

        // Lamp sits just above the top of the frame, offset 0.7 m into the room for a 30°+ angle.
        let lampHeight = paintingPos.y + Float(paintingSize / 2) + 0.20
        let inwardOffset: Float = 0.7
        let lampPos: SCNVector3
        switch wall {
        case .north: lampPos = SCNVector3(paintingPos.x, lampHeight, paintingPos.z + inwardOffset)
        case .south: lampPos = SCNVector3(paintingPos.x, lampHeight, paintingPos.z - inwardOffset)
        case .east:  lampPos = SCNVector3(paintingPos.x - inwardOffset, lampHeight, paintingPos.z)
        case .west:  lampPos = SCNVector3(paintingPos.x + inwardOffset, lampHeight, paintingPos.z)
        }
        lightNode.position = lampPos
        lightNode.look(at: paintingPos)
        scene.rootNode.addChildNode(lightNode)

        // Visible brass picture-lamp body (cylinder hanging from a thin arm).
        addPictureLampBody(at: lampPos, paintingPos: paintingPos, wall: wall, in: scene)
    }

    private static func addPictureLampBody(at lampPos: SCNVector3, paintingPos: SCNVector3, wall: WallDirection, in scene: SCNScene) {
        let brass = SCNMaterial()
        brass.diffuse.contents = UIColor(red: 0.72, green: 0.55, blue: 0.22, alpha: 1.0)
        brass.metalness.contents = 0.85
        brass.roughness.contents = 0.30
        brass.lightingModel = .physicallyBased

        // Lamp head — short horizontal cylinder.
        let head = SCNCylinder(radius: 0.05, height: 0.30)
        head.materials = [brass]
        let headNode = SCNNode(geometry: head)
        headNode.position = lampPos
        // Rotate so the cylinder lies parallel to the wall.
        switch wall {
        case .north, .south: headNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2) // along X
        case .east,  .west:  headNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0) // along Z
        }
        scene.rootNode.addChildNode(headNode)

        // Thin arm connecting wall to lamp (small box).
        let armLen: CGFloat = 0.7
        let arm = SCNBox(width: 0.015, height: 0.015, length: armLen, chamferRadius: 0.002)
        arm.materials = [brass]
        let armNode = SCNNode(geometry: arm)
        // Place arm midway between wall and lamp.
        switch wall {
        case .north: armNode.position = SCNVector3(paintingPos.x, lampPos.y + 0.05, (paintingPos.z + lampPos.z) / 2)
        case .south: armNode.position = SCNVector3(paintingPos.x, lampPos.y + 0.05, (paintingPos.z + lampPos.z) / 2)
        case .east:  armNode.position = SCNVector3((paintingPos.x + lampPos.x) / 2, lampPos.y + 0.05, paintingPos.z); armNode.eulerAngles.y = .pi / 2
        case .west:  armNode.position = SCNVector3((paintingPos.x + lampPos.x) / 2, lampPos.y + 0.05, paintingPos.z); armNode.eulerAngles.y = .pi / 2
        }
        scene.rootNode.addChildNode(armNode)
    }

    private static func makePaintingNode(for artwork: NFTArtwork) -> SCNNode {
        let group = SCNNode()
        group.name = "painting_\(artwork.id.uuidString)"

        let sourceImage = ImageLoader.cachedOrPlaceholder(for: artwork)
        let cacheKey = artwork.id.uuidString

        let canvas = SCNPlane(width: paintingSize, height: paintingSize)
        canvas.cornerRadius = 0.02
        canvas.widthSegmentCount = 32
        canvas.heightSegmentCount = 32

        // Initial material: diffuse only — instant render, no Sobel work yet.
        let mat = SCNMaterial()
        mat.diffuse.contents = sourceImage
        mat.roughness.contents = 0.45
        mat.metalness.contents = 0.03
        mat.lightingModel = .physicallyBased
        canvas.materials = [mat]

        let canvasNode = SCNNode(geometry: canvas)
        canvasNode.position = SCNVector3(0, 0, 0.01)
        group.addChildNode(canvasNode)

        // Frame (4 bars in dark metal).
        addFrame(around: paintingSize, to: group)

        // Enrich with normal/height maps in the background. Apply on the main thread
        // so SceneKit doesn't see partial writes mid-frame.
        Task.detached(priority: .utility) {
            // Network/disk fetch (no-op if already in memory).
            let highRes = await ImageLoader.loadImage(for: artwork)
            NormalMapGenerator.invalidate(cacheKey: cacheKey)
            let normalMap = NormalMapGenerator.generate(from: highRes, cacheKey: cacheKey)
            let heightMap = NormalMapGenerator.generateHeightmap(from: highRes, cacheKey: cacheKey)
            await MainActor.run {
                mat.diffuse.contents = highRes
                mat.normal.contents = normalMap
                mat.normal.intensity = 1.5
                mat.displacement.contents = heightMap
                mat.displacement.intensity = 0.012
            }
        }

        return group
    }

    private static func addFrame(around innerSize: CGFloat, to parent: SCNNode) {
        let thickness: CGFloat = 0.07
        let depth: CGFloat = 0.06

        // Burnished gold-leaf frame, classic gallery look.
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(red: 0.62, green: 0.48, blue: 0.18, alpha: 1.0)
        mat.roughness.contents = 0.35
        mat.metalness.contents = 0.75
        mat.lightingModel = .physicallyBased

        let configs: [(CGFloat, CGFloat, SCNVector3)] = [
            (innerSize + thickness * 2, thickness, SCNVector3(0, Float(innerSize / 2 + thickness / 2), Float(-depth / 2 + 0.005))),
            (innerSize + thickness * 2, thickness, SCNVector3(0, Float(-innerSize / 2 - thickness / 2), Float(-depth / 2 + 0.005))),
            (thickness, innerSize, SCNVector3(Float(-innerSize / 2 - thickness / 2), 0, Float(-depth / 2 + 0.005))),
            (thickness, innerSize, SCNVector3(Float(innerSize / 2 + thickness / 2), 0, Float(-depth / 2 + 0.005))),
        ]
        for (w, h, pos) in configs {
            let bar = SCNBox(width: w, height: h, length: depth, chamferRadius: 0.005)
            bar.materials = [mat]
            let node = SCNNode(geometry: bar)
            node.position = pos
            parent.addChildNode(node)
        }
    }

    // MARK: - Lighting

    private static func addLighting(to scene: SCNScene) {
        // Warm ambient — diffuse base light bouncing off cream walls.
        let ambient = SCNNode()
        ambient.name = "showroom_ambient"
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 320
        ambient.light?.color = UIColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 1.0)
        scene.rootNode.addChildNode(ambient)

        // Soft top-down area light from the ceiling — broad fill, no harsh hot spots.
        let fill = SCNNode()
        fill.name = "showroom_fill"
        fill.light = SCNLight()
        fill.light?.type = .area
        fill.light?.intensity = 350
        fill.light?.areaType = .rectangle
        fill.light?.areaExtents = simd_float3(Float(roomSize) * 0.7, Float(roomSize) * 0.7, 0)
        fill.light?.color = UIColor(red: 1.0, green: 0.97, blue: 0.92, alpha: 1.0)
        fill.position = SCNVector3(0, roomHeight - 0.05, 0)
        fill.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0) // shine downward
        scene.rootNode.addChildNode(fill)

        // Faint omnidirectional centre lamp — gives the floor / room mid-tones some life.
        let centre = SCNNode()
        centre.name = "showroom_centre"
        centre.light = SCNLight()
        centre.light?.type = .omni
        centre.light?.intensity = 180
        centre.light?.color = UIColor(red: 1.0, green: 0.93, blue: 0.78, alpha: 1.0)
        centre.light?.attenuationStartDistance = 1.5
        centre.light?.attenuationEndDistance = 8
        centre.position = SCNVector3(0, roomHeight * 0.6, 0)
        scene.rootNode.addChildNode(centre)
    }

    // MARK: - Theme switching

    /// Mutates an existing scene in place to apply a lighting theme. Called when the user
    /// toggles the day/night/gallery button at runtime.
    static func applyLighting(_ mode: ShowroomView.LightingMode, to scene: SCNScene) {
        let bgColor: UIColor
        let ambientIntensity: CGFloat
        let ambientColor: UIColor
        let fillIntensity: CGFloat
        let pictureIntensity: CGFloat
        let pictureColor: UIColor

        switch mode {
        case .gallery:
            bgColor = UIColor(red: 0.10, green: 0.08, blue: 0.06, alpha: 1.0)
            ambientIntensity = 320
            ambientColor = UIColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 1.0)
            fillIntensity = 350
            pictureIntensity = 25
            pictureColor = UIColor(red: 1.0, green: 0.93, blue: 0.78, alpha: 1.0)
        case .day:
            bgColor = UIColor(red: 0.78, green: 0.86, blue: 0.95, alpha: 1.0)
            ambientIntensity = 700
            ambientColor = UIColor(white: 1.0, alpha: 1.0)
            fillIntensity = 600
            pictureIntensity = 10
            pictureColor = UIColor(red: 1.0, green: 0.99, blue: 0.96, alpha: 1.0)
        case .night:
            bgColor = UIColor(red: 0.02, green: 0.03, blue: 0.06, alpha: 1.0)
            ambientIntensity = 90
            ambientColor = UIColor(red: 0.5, green: 0.55, blue: 0.7, alpha: 1.0)
            fillIntensity = 80
            pictureIntensity = 60
            pictureColor = UIColor(red: 1.0, green: 0.88, blue: 0.65, alpha: 1.0)
        }

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.4
        scene.background.contents = bgColor
        scene.rootNode.enumerateChildNodes { node, _ in
            guard let name = node.name else { return }
            switch name {
            case "showroom_ambient":
                node.light?.intensity = ambientIntensity
                node.light?.color = ambientColor
            case "showroom_fill", "showroom_centre":
                node.light?.intensity = fillIntensity
            case "showroom_picture_light":
                node.light?.intensity = pictureIntensity
                node.light?.color = pictureColor
            default: break
            }
        }
        SCNTransaction.commit()
    }

    // MARK: - Decor

    /// Adds gallery furnishings: a central runner rug, two viewing benches, four corner
    /// pedestals with marble vases, and a multi-bulb chandelier hanging from the ceiling.
    private static func addDecor(to scene: SCNScene) {
        addRug(to: scene)
        addBench(to: scene, position: SCNVector3(-1.6, 0.0, 0))
        addBench(to: scene, position: SCNVector3( 1.6, 0.0, 0))
        addPedestal(to: scene, position: SCNVector3(-4.6, 0.0, -4.6))
        addPedestal(to: scene, position: SCNVector3( 4.6, 0.0, -4.6))
        addPedestal(to: scene, position: SCNVector3(-4.6, 0.0,  4.6))
        addPedestal(to: scene, position: SCNVector3( 4.6, 0.0,  4.6))
        addChandelier(to: scene)
    }

    private static func addRug(to scene: SCNScene) {
        let rug = SCNPlane(width: 4.0, height: 8.0)
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(red: 0.55, green: 0.18, blue: 0.18, alpha: 1.0) // burgundy
        mat.roughness.contents = 0.95
        mat.metalness.contents = 0.0
        mat.lightingModel = .lambert
        rug.materials = [mat]

        let node = SCNNode(geometry: rug)
        node.eulerAngles.x = -.pi / 2
        node.position = SCNVector3(0, 0.005, 0) // sit on the floor
        scene.rootNode.addChildNode(node)
    }

    private static func addBench(to scene: SCNScene, position: SCNVector3) {
        let woodMat = SCNMaterial()
        woodMat.diffuse.contents = UIColor(red: 0.30, green: 0.20, blue: 0.12, alpha: 1.0)
        woodMat.roughness.contents = 0.7
        woodMat.metalness.contents = 0.0
        woodMat.lightingModel = .physicallyBased

        // Top slab.
        let top = SCNBox(width: 0.4, height: 0.06, length: 1.4, chamferRadius: 0.01)
        top.materials = [woodMat]
        let topNode = SCNNode(geometry: top)
        topNode.position = SCNVector3(position.x, 0.42, position.z)
        scene.rootNode.addChildNode(topNode)

        // Four legs.
        let legPositions: [(Float, Float)] = [(-0.16, -0.6), (0.16, -0.6), (-0.16, 0.6), (0.16, 0.6)]
        for (dx, dz) in legPositions {
            let leg = SCNBox(width: 0.05, height: 0.39, length: 0.05, chamferRadius: 0.005)
            leg.materials = [woodMat]
            let legNode = SCNNode(geometry: leg)
            legNode.position = SCNVector3(position.x + dx, 0.195, position.z + dz)
            scene.rootNode.addChildNode(legNode)
        }
    }

    private static func addPedestal(to scene: SCNScene, position: SCNVector3) {
        let marble = SCNMaterial()
        marble.diffuse.contents = UIColor(red: 0.92, green: 0.90, blue: 0.85, alpha: 1.0)
        marble.roughness.contents = 0.25
        marble.metalness.contents = 0.05
        marble.lightingModel = .physicallyBased

        // Pedestal column.
        let column = SCNBox(width: 0.45, height: 1.0, length: 0.45, chamferRadius: 0.02)
        column.materials = [marble]
        let columnNode = SCNNode(geometry: column)
        columnNode.position = SCNVector3(position.x, 0.5, position.z)
        scene.rootNode.addChildNode(columnNode)

        // Decorative vase on top: tall body + neck.
        let vaseMat = SCNMaterial()
        vaseMat.diffuse.contents = UIColor(red: 0.18, green: 0.32, blue: 0.40, alpha: 1.0) // ceramic blue
        vaseMat.roughness.contents = 0.20
        vaseMat.metalness.contents = 0.10
        vaseMat.lightingModel = .physicallyBased

        let vaseBody = SCNSphere(radius: 0.18)
        vaseBody.materials = [vaseMat]
        let bodyNode = SCNNode(geometry: vaseBody)
        bodyNode.position = SCNVector3(position.x, 1.18, position.z)
        bodyNode.scale = SCNVector3(1.0, 1.4, 1.0) // elongated
        scene.rootNode.addChildNode(bodyNode)

        let vaseNeck = SCNCylinder(radius: 0.06, height: 0.10)
        vaseNeck.materials = [vaseMat]
        let neckNode = SCNNode(geometry: vaseNeck)
        neckNode.position = SCNVector3(position.x, 1.45, position.z)
        scene.rootNode.addChildNode(neckNode)
    }

    private static func addChandelier(to scene: SCNScene) {
        let brass = SCNMaterial()
        brass.diffuse.contents = UIColor(red: 0.72, green: 0.55, blue: 0.22, alpha: 1.0)
        brass.metalness.contents = 0.85
        brass.roughness.contents = 0.30
        brass.lightingModel = .physicallyBased

        let glow = SCNMaterial()
        glow.diffuse.contents = UIColor(red: 1.0, green: 0.92, blue: 0.70, alpha: 1.0)
        glow.emission.contents = UIColor(red: 1.0, green: 0.85, blue: 0.55, alpha: 1.0)
        glow.lightingModel = .lambert

        // Ceiling rod.
        let rod = SCNCylinder(radius: 0.015, height: 0.4)
        rod.materials = [brass]
        let rodNode = SCNNode(geometry: rod)
        rodNode.position = SCNVector3(0, roomHeight - 0.20, 0)
        scene.rootNode.addChildNode(rodNode)

        // Central hub sphere.
        let hub = SCNSphere(radius: 0.12)
        hub.materials = [brass]
        let hubNode = SCNNode(geometry: hub)
        hubNode.position = SCNVector3(0, roomHeight - 0.45, 0)
        scene.rootNode.addChildNode(hubNode)

        // Six glowing bulbs around the hub.
        let bulbCount = 6
        let radius: Float = 0.45
        for i in 0..<bulbCount {
            let angle = Float(i) * (2 * .pi / Float(bulbCount))
            let bulb = SCNSphere(radius: 0.07)
            bulb.materials = [glow]
            let bulbNode = SCNNode(geometry: bulb)
            bulbNode.position = SCNVector3(
                radius * cos(angle),
                roomHeight - 0.5,
                radius * sin(angle)
            )
            scene.rootNode.addChildNode(bulbNode)
        }
    }

    // MARK: - Camera

    private static func addCamera(to scene: SCNScene) {
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 65
        cameraNode.camera?.zNear = 0.1
        cameraNode.camera?.zFar = 60
        cameraNode.camera?.wantsHDR = true
        // Start in the centre of the room at eye level.
        cameraNode.position = SCNVector3(0, paintingCentreY, 0)
        cameraNode.eulerAngles = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(cameraNode)
    }
}

// MARK: - Wall geometry helpers

private enum WallDirection: CaseIterable {
    case north, south, east, west

    /// Where the centre of the wall sits in world space.
    func wallCentre(roomSize: Float, roomHeight: Float, thickness: Float) -> SCNVector3 {
        let halfRoom = roomSize / 2
        let halfHeight = roomHeight / 2
        let inset = halfRoom + thickness / 2
        switch self {
        case .north: return SCNVector3(0, halfHeight, -inset)
        case .south: return SCNVector3(0, halfHeight, inset)
        case .east:  return SCNVector3(inset, halfHeight, 0)
        case .west:  return SCNVector3(-inset, halfHeight, 0)
        }
    }

    /// Y rotation for the wall geometry so its inner surface faces the room centre.
    var wallRotationY: Float {
        switch self {
        case .north, .south: return 0
        case .east, .west:   return .pi / 2
        }
    }

    /// Where a painting hung on this wall is placed, given offset along the wall and a Y height.
    func paintingPosition(roomSize: Float, paintingY: Float, alongWall: Float, wallThickness: Float) -> SCNVector3 {
        // Place painting just in front of the wall (small bias so it doesn't z-fight).
        let bias: Float = wallThickness / 2 + 0.02
        let halfRoom = roomSize / 2
        switch self {
        case .north: return SCNVector3(alongWall, paintingY, -halfRoom + bias)
        case .south: return SCNVector3(alongWall, paintingY,  halfRoom - bias)
        case .east:  return SCNVector3(halfRoom - bias, paintingY, alongWall)
        case .west:  return SCNVector3(-halfRoom + bias, paintingY, alongWall)
        }
    }

    /// Y rotation for the painting plane so its front face looks toward the room centre.
    var paintingRotationY: Float {
        switch self {
        case .north: return 0
        case .south: return .pi
        case .east:  return -.pi / 2
        case .west:  return .pi / 2
        }
    }

}
