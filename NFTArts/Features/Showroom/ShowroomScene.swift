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
    static func build(artworks: [NFTArtwork], theme: ShowroomTheme = .louvre) -> SCNScene {
        let scene = SCNScene()
        let palette = theme.palette
        scene.background.contents = palette.background

        addFloor(to: scene, palette: palette)
        addCeiling(to: scene, palette: palette)
        addWalls(to: scene, palette: palette)
        addPaintings(to: scene, artworks: Array(artworks.prefix(12)), palette: palette)
        addLighting(to: scene, palette: palette)
        // Декор зависит от темы: каждой свой набор.
        addRug(to: scene, palette: palette)
        switch theme {
        case .louvre:    addLouvreDecor(to: scene)
        case .modern:    addModernDecor(to: scene, palette: palette)
        case .loft:      addLoftDecor(to: scene, palette: palette)
        case .cyberpunk: addCyberpunkDecor(to: scene, palette: palette)
        }
        addCamera(to: scene)

        return scene
    }

    // MARK: - Floor & ceiling

    private static func addFloor(to scene: SCNScene, palette: ShowroomTheme.Palette) {
        let plane = SCNPlane(width: CGFloat(roomSize), height: CGFloat(roomSize))
        let mat = SCNMaterial()
        mat.diffuse.contents = palette.floorColor
        mat.diffuse.contentsTransform = SCNMatrix4MakeScale(6, 6, 1)
        mat.diffuse.wrapS = .repeat
        mat.diffuse.wrapT = .repeat
        mat.roughness.contents = palette.floorRoughness
        mat.metalness.contents = 0.0
        mat.lightingModel = .physicallyBased
        plane.materials = [mat]

        let node = SCNNode(geometry: plane)
        node.eulerAngles.x = -.pi / 2
        scene.rootNode.addChildNode(node)
    }

    private static func addCeiling(to scene: SCNScene, palette: ShowroomTheme.Palette) {
        let plane = SCNPlane(width: CGFloat(roomSize), height: CGFloat(roomSize))
        let mat = SCNMaterial()
        mat.diffuse.contents = palette.ceilingColor
        mat.lightingModel = .lambert
        mat.isDoubleSided = true
        plane.materials = [mat]

        let node = SCNNode(geometry: plane)
        node.position = SCNVector3(0, roomHeight, 0)
        node.eulerAngles.x = .pi / 2
        scene.rootNode.addChildNode(node)
    }

    // MARK: - Walls

    private static func addWalls(to scene: SCNScene, palette: ShowroomTheme.Palette) {
        let wallMat = SCNMaterial()
        wallMat.diffuse.contents = palette.wallColor
        wallMat.roughness.contents = palette.wallRoughness
        wallMat.metalness.contents = 0.0
        wallMat.lightingModel = .physicallyBased

        let trimMat = SCNMaterial()
        trimMat.diffuse.contents = palette.trimColor
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
    private static func addPaintings(to scene: SCNScene, artworks: [NFTArtwork], palette: ShowroomTheme.Palette) {
        guard !artworks.isEmpty else { return }

        let walls = WallDirection.allCases
        var perWall: [WallDirection: [NFTArtwork]] = [:]
        for (i, art) in artworks.enumerated() {
            let wall = walls[i % walls.count]
            perWall[wall, default: []].append(art)
        }

        for (direction, items) in perWall {
            place(artworks: items, on: direction, in: scene, palette: palette)
        }
    }

    private static func place(artworks: [NFTArtwork], on wall: WallDirection, in scene: SCNScene, palette: ShowroomTheme.Palette) {
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
            let paintingNode = makePaintingNode(for: artwork, palette: palette)
            paintingNode.position = position
            paintingNode.eulerAngles.y = wall.paintingRotationY
            scene.rootNode.addChildNode(paintingNode)

            addPictureLight(at: position, wall: wall, in: scene, palette: palette)
        }
    }

    /// Museum-style "picture lamp": mounted above the frame, angled 30° down at the canvas.
    /// Wide enough cone (45°) to cover the whole 1.6 m painting evenly, no hard edge fall-off.
    /// Adds a small brass arm + lamp head as visible geometry above the frame.
    private static func addPictureLight(at paintingPos: SCNVector3, wall: WallDirection, in scene: SCNScene, palette: ShowroomTheme.Palette) {
        let lightNode = SCNNode()
        lightNode.name = "showroom_picture_light"
        let light = SCNLight()
        light.type = .spot
        light.intensity = palette.pictureIntensity
        light.spotInnerAngle = 50
        light.spotOuterAngle = 90
        light.color = palette.pictureColor
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

    private static func makePaintingNode(for artwork: NFTArtwork, palette: ShowroomTheme.Palette) -> SCNNode {
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

        addFrame(around: paintingSize, to: group, palette: palette)

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

    private static func addFrame(around innerSize: CGFloat, to parent: SCNNode, palette: ShowroomTheme.Palette) {
        let thickness: CGFloat = 0.07
        let depth: CGFloat = 0.06

        let mat = SCNMaterial()
        mat.diffuse.contents = palette.frameDiffuse
        mat.roughness.contents = palette.frameRoughness
        mat.metalness.contents = palette.frameMetalness
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

    private static func addLighting(to scene: SCNScene, palette: ShowroomTheme.Palette) {
        let ambient = SCNNode()
        ambient.name = "showroom_ambient"
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = palette.ambientIntensity
        ambient.light?.color = palette.ambientColor
        scene.rootNode.addChildNode(ambient)

        let fill = SCNNode()
        fill.name = "showroom_fill"
        fill.light = SCNLight()
        fill.light?.type = .area
        fill.light?.intensity = palette.fillIntensity
        fill.light?.areaType = .rectangle
        fill.light?.areaExtents = simd_float3(Float(roomSize) * 0.7, Float(roomSize) * 0.7, 0)
        fill.light?.color = palette.ambientColor
        fill.position = SCNVector3(0, roomHeight - 0.05, 0)
        fill.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        scene.rootNode.addChildNode(fill)

        let centre = SCNNode()
        centre.name = "showroom_centre"
        centre.light = SCNLight()
        centre.light?.type = .omni
        centre.light?.intensity = palette.fillIntensity * 0.5
        centre.light?.color = palette.pictureColor
        centre.light?.attenuationStartDistance = 1.5
        centre.light?.attenuationEndDistance = 8
        centre.position = SCNVector3(0, roomHeight * 0.6, 0)
        scene.rootNode.addChildNode(centre)
    }

    // MARK: - Lighting modifier (поверх палитры темы)

    /// Применяет к существующей сцене модификатор освещения, не меняя палитру/декор.
    /// Используется при тапе на кнопку лампочки в шоуруме.
    static func applyLighting(_ mode: ShowroomView.LightingMode, themePalette: ShowroomTheme.Palette, to scene: SCNScene) {
        let ambientMult: CGFloat
        let fillMult: CGFloat
        let pictureMult: CGFloat
        let bg: UIColor

        switch mode {
        case .gallery:
            ambientMult = 1.0; fillMult = 1.0; pictureMult = 1.0
            bg = themePalette.background
        case .day:
            ambientMult = 2.2; fillMult = 1.8; pictureMult = 0.6
            bg = UIColor(red: 0.86, green: 0.91, blue: 0.96, alpha: 1.0)
        case .night:
            ambientMult = 0.25; fillMult = 0.3; pictureMult = 2.8
            bg = UIColor(red: 0.02, green: 0.03, blue: 0.06, alpha: 1.0)
        }

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.4
        scene.background.contents = bg
        scene.rootNode.enumerateChildNodes { node, _ in
            guard let name = node.name else { return }
            switch name {
            case "showroom_ambient":
                node.light?.intensity = themePalette.ambientIntensity * ambientMult
            case "showroom_fill", "showroom_centre":
                node.light?.intensity = themePalette.fillIntensity * fillMult
            case "showroom_picture_light":
                node.light?.intensity = themePalette.pictureIntensity * pictureMult
            default: break
            }
        }
        SCNTransaction.commit()
    }

    // MARK: - Decor

    /// Adds gallery furnishings: a central runner rug, two viewing benches, four corner
    /// pedestals with marble vases, and a multi-bulb chandelier hanging from the ceiling.
    private static func addLouvreDecor(to scene: SCNScene) {
        addBench(to: scene, position: SCNVector3(-1.6, 0.0, 0))
        addBench(to: scene, position: SCNVector3( 1.6, 0.0, 0))
        addPedestal(to: scene, position: SCNVector3(-4.6, 0.0, -4.6))
        addPedestal(to: scene, position: SCNVector3( 4.6, 0.0, -4.6))
        addPedestal(to: scene, position: SCNVector3(-4.6, 0.0,  4.6))
        addPedestal(to: scene, position: SCNVector3( 4.6, 0.0,  4.6))
        addChandelier(to: scene)
    }

    // MARK: - Modern decor (минимализм: куб-postaments + abstract sculptures)
    private static func addModernDecor(to scene: SCNScene, palette: ShowroomTheme.Palette) {
        // Низкие квадратные постаменты с абстрактными скульптурами
        let positions: [SCNVector3] = [
            SCNVector3(-4.5, 0, -4.5), SCNVector3(4.5, 0, -4.5),
            SCNVector3(-4.5, 0,  4.5), SCNVector3(4.5, 0,  4.5)
        ]
        for (i, pos) in positions.enumerated() {
            addMinimalistPedestal(to: scene, position: pos, sculptureType: i % 3)
        }
        // Длинная белая скамья в центре
        addModernBench(to: scene, position: SCNVector3(0, 0, 0))
    }

    private static func addMinimalistPedestal(to scene: SCNScene, position: SCNVector3, sculptureType: Int) {
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1.0)
        mat.roughness.contents = 0.4
        mat.metalness.contents = 0.05
        mat.lightingModel = .physicallyBased

        let pedestal = SCNBox(width: 0.5, height: 0.6, length: 0.5, chamferRadius: 0.0)
        pedestal.materials = [mat]
        let pNode = SCNNode(geometry: pedestal)
        pNode.position = SCNVector3(position.x, 0.3, position.z)
        scene.rootNode.addChildNode(pNode)

        // Абстрактная скульптура — варьируется по типу
        let sculpMat = SCNMaterial()
        sculpMat.diffuse.contents = UIColor(red: 0.15, green: 0.15, blue: 0.17, alpha: 1.0)
        sculpMat.metalness.contents = 0.7
        sculpMat.roughness.contents = 0.2
        sculpMat.lightingModel = .physicallyBased

        let sculpture: SCNGeometry
        switch sculptureType {
        case 0: sculpture = SCNTorus(ringRadius: 0.18, pipeRadius: 0.05)
        case 1: sculpture = SCNSphere(radius: 0.16)
        default: sculpture = SCNCone(topRadius: 0.0, bottomRadius: 0.15, height: 0.35)
        }
        sculpture.materials = [sculpMat]
        let sNode = SCNNode(geometry: sculpture)
        sNode.position = SCNVector3(position.x, 0.75, position.z)
        if sculptureType == 0 { sNode.eulerAngles.x = .pi / 2 }
        scene.rootNode.addChildNode(sNode)
    }

    private static func addModernBench(to scene: SCNScene, position: SCNVector3) {
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(red: 0.92, green: 0.92, blue: 0.93, alpha: 1.0)
        mat.roughness.contents = 0.5
        mat.lightingModel = .physicallyBased

        let bench = SCNBox(width: 2.4, height: 0.35, length: 0.5, chamferRadius: 0.02)
        bench.materials = [mat]
        let node = SCNNode(geometry: bench)
        node.position = SCNVector3(position.x, 0.18, position.z)
        scene.rootNode.addChildNode(node)
    }

    // MARK: - Loft decor (индастриал: эдисон-лампы на проводах, низкие диваны, ящики)
    private static func addLoftDecor(to scene: SCNScene, palette: ShowroomTheme.Palette) {
        // Висящие Эдисон-лампочки
        addEdisonBulb(to: scene, position: SCNVector3(-2.5, 0, -2.5))
        addEdisonBulb(to: scene, position: SCNVector3( 2.5, 0, -2.5))
        addEdisonBulb(to: scene, position: SCNVector3(-2.5, 0,  2.5))
        addEdisonBulb(to: scene, position: SCNVector3( 2.5, 0,  2.5))
        // Низкие кожаные диванчики
        addLeatherCouch(to: scene, position: SCNVector3(-1.8, 0, 0))
        addLeatherCouch(to: scene, position: SCNVector3( 1.8, 0, 0))
        // Деревянные ящики в углах
        addCrate(to: scene, position: SCNVector3(-4.6, 0, -4.6))
        addCrate(to: scene, position: SCNVector3( 4.6, 0,  4.6))
    }

    private static func addEdisonBulb(to scene: SCNScene, position: SCNVector3) {
        // Длинный шнур от потолка
        let cordMat = SCNMaterial()
        cordMat.diffuse.contents = UIColor(red: 0.1, green: 0.08, blue: 0.06, alpha: 1.0)
        cordMat.lightingModel = .lambert
        let cord = SCNCylinder(radius: 0.008, height: 2.0)
        cord.materials = [cordMat]
        let cordNode = SCNNode(geometry: cord)
        cordNode.position = SCNVector3(position.x, 3.4, position.z)
        scene.rootNode.addChildNode(cordNode)

        // Лампочка
        let bulbMat = SCNMaterial()
        bulbMat.diffuse.contents = UIColor(red: 1.0, green: 0.85, blue: 0.5, alpha: 1.0)
        bulbMat.emission.contents = UIColor(red: 1.0, green: 0.75, blue: 0.4, alpha: 1.0)
        bulbMat.lightingModel = .lambert
        let bulb = SCNSphere(radius: 0.09)
        bulb.materials = [bulbMat]
        let bulbNode = SCNNode(geometry: bulb)
        bulbNode.position = SCNVector3(position.x, 2.35, position.z)
        scene.rootNode.addChildNode(bulbNode)

        // Точечный свет рядом — тёплая лампа накаливания
        let lightNode = SCNNode()
        lightNode.name = "showroom_picture_light" // совместимо с applyLighting
        lightNode.light = SCNLight()
        lightNode.light?.type = .omni
        lightNode.light?.intensity = 90
        lightNode.light?.color = UIColor(red: 1.0, green: 0.75, blue: 0.4, alpha: 1.0)
        lightNode.light?.attenuationStartDistance = 0.5
        lightNode.light?.attenuationEndDistance = 4
        lightNode.position = SCNVector3(position.x, 2.3, position.z)
        scene.rootNode.addChildNode(lightNode)
    }

    private static func addLeatherCouch(to scene: SCNScene, position: SCNVector3) {
        let leather = SCNMaterial()
        leather.diffuse.contents = UIColor(red: 0.35, green: 0.22, blue: 0.15, alpha: 1.0)
        leather.roughness.contents = 0.55
        leather.metalness.contents = 0.05
        leather.lightingModel = .physicallyBased
        // Сиденье
        let seat = SCNBox(width: 0.55, height: 0.45, length: 1.4, chamferRadius: 0.06)
        seat.materials = [leather]
        let seatNode = SCNNode(geometry: seat)
        seatNode.position = SCNVector3(position.x, 0.22, position.z)
        scene.rootNode.addChildNode(seatNode)
        // Спинка
        let back = SCNBox(width: 0.2, height: 0.55, length: 1.4, chamferRadius: 0.04)
        back.materials = [leather]
        let backNode = SCNNode(geometry: back)
        let backOffset: Float = position.x < 0 ? -0.22 : 0.22
        backNode.position = SCNVector3(position.x + backOffset, 0.5, position.z)
        scene.rootNode.addChildNode(backNode)
    }

    private static func addCrate(to scene: SCNScene, position: SCNVector3) {
        let wood = SCNMaterial()
        wood.diffuse.contents = UIColor(red: 0.30, green: 0.20, blue: 0.12, alpha: 1.0)
        wood.roughness.contents = 0.85
        wood.lightingModel = .physicallyBased
        let box = SCNBox(width: 0.55, height: 0.55, length: 0.55, chamferRadius: 0.01)
        box.materials = [wood]
        let node = SCNNode(geometry: box)
        node.position = SCNVector3(position.x, 0.275, position.z)
        scene.rootNode.addChildNode(node)
    }

    // MARK: - Cyberpunk decor (неон-трубы, голограммы, металл-постаменты)
    private static func addCyberpunkDecor(to scene: SCNScene, palette: ShowroomTheme.Palette) {
        // Неоновые полосы вдоль низа стен
        addNeonStrip(to: scene, color: UIColor(red: 0.85, green: 0.10, blue: 0.55, alpha: 1.0))
        // Голограммы — emissive кубики на тонких подставках
        addHologram(to: scene, position: SCNVector3(-4.0, 0, -4.0), color: UIColor(red: 0.30, green: 0.85, blue: 1.0, alpha: 1.0))
        addHologram(to: scene, position: SCNVector3( 4.0, 0, -4.0), color: UIColor(red: 0.85, green: 0.10, blue: 0.55, alpha: 1.0))
        addHologram(to: scene, position: SCNVector3(-4.0, 0,  4.0), color: UIColor(red: 0.55, green: 0.30, blue: 0.95, alpha: 1.0))
        addHologram(to: scene, position: SCNVector3( 4.0, 0,  4.0), color: UIColor(red: 0.30, green: 0.85, blue: 1.0, alpha: 1.0))
        // Центральная неон-инсталляция (вертикальная капсула)
        addNeonPillar(to: scene)
    }

    private static func addNeonStrip(to scene: SCNScene, color: UIColor) {
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.emission.contents = color
        mat.lightingModel = .lambert

        for direction in [-1, 1] {
            let strip = SCNBox(width: CGFloat(roomSize * 0.9), height: 0.04, length: 0.04, chamferRadius: 0.01)
            strip.materials = [mat]
            let north = SCNNode(geometry: strip)
            north.position = SCNVector3(0, 0.1, Float(direction) * (roomSize / 2 - 0.1))
            scene.rootNode.addChildNode(north)

            let east = SCNNode(geometry: strip)
            east.position = SCNVector3(Float(direction) * (roomSize / 2 - 0.1), 0.1, 0)
            east.eulerAngles.y = .pi / 2
            scene.rootNode.addChildNode(east)
        }
    }

    private static func addHologram(to scene: SCNScene, position: SCNVector3, color: UIColor) {
        // Тонкий металлический постамент
        let baseMat = SCNMaterial()
        baseMat.diffuse.contents = UIColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0)
        baseMat.metalness.contents = 0.9
        baseMat.roughness.contents = 0.2
        baseMat.lightingModel = .physicallyBased
        let base = SCNCylinder(radius: 0.18, height: 0.6)
        base.materials = [baseMat]
        let baseNode = SCNNode(geometry: base)
        baseNode.position = SCNVector3(position.x, 0.3, position.z)
        scene.rootNode.addChildNode(baseNode)

        // Голограмма (светящийся икосаэдр-подобный объект)
        let holoMat = SCNMaterial()
        holoMat.diffuse.contents = color
        holoMat.emission.contents = color
        holoMat.transparency = 0.65
        holoMat.lightingModel = .lambert
        let holo = SCNSphere(radius: 0.22)
        holo.segmentCount = 8
        holo.materials = [holoMat]
        let holoNode = SCNNode(geometry: holo)
        holoNode.position = SCNVector3(position.x, 0.85, position.z)
        // Медленное вращение
        let spin = SCNAction.rotateBy(x: 0, y: 2 * .pi, z: 0, duration: 8)
        holoNode.runAction(SCNAction.repeatForever(spin))
        scene.rootNode.addChildNode(holoNode)
    }

    private static func addNeonPillar(to scene: SCNScene) {
        let pillarMat = SCNMaterial()
        pillarMat.diffuse.contents = UIColor(red: 0.30, green: 0.85, blue: 1.0, alpha: 1.0)
        pillarMat.emission.contents = UIColor(red: 0.30, green: 0.85, blue: 1.0, alpha: 1.0)
        pillarMat.transparency = 0.8
        pillarMat.lightingModel = .lambert

        let pillar = SCNCapsule(capRadius: 0.06, height: 2.5)
        pillar.materials = [pillarMat]
        let node = SCNNode(geometry: pillar)
        node.position = SCNVector3(0, 1.25, 0)
        scene.rootNode.addChildNode(node)
    }

    private static func addRug(to scene: SCNScene, palette: ShowroomTheme.Palette) {
        let rug = SCNPlane(width: 4.0, height: 8.0)
        let mat = SCNMaterial()
        mat.diffuse.contents = palette.rugColor
        mat.roughness.contents = 0.95
        mat.metalness.contents = 0.0
        mat.lightingModel = .lambert
        rug.materials = [mat]

        let node = SCNNode(geometry: rug)
        node.eulerAngles.x = -.pi / 2
        node.position = SCNVector3(0, 0.005, 0)
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
