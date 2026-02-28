import SwiftUI
import ARKit
import RealityKit
import Photos

// MARK: - AR Showroom View

/// Fullscreen AR experience with CosmoDreams-inspired mechanics:
/// - Wall & floor placement with improved detection
/// - Gallery mode (multiple artworks)
/// - Photo capture
/// - "Living painting" animated lighting
/// - Dimension indicator
struct ARShowroomView: View {
    let artwork: NFTArtwork
    @EnvironmentObject var auctionService: AuctionService
    @Environment(\.dismiss) private var dismiss

    @State private var placedCount = 0
    @State private var placementInfo = ""
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var showGalleryPicker = false
    @State private var currentDimensions = ""
    @State private var surfaceMode: SurfaceMode = .auto

    enum SurfaceMode: String, CaseIterable {
        case auto, wall, floor
    }

    var body: some View {
        ZStack {
            ARShowroomRepresentable(
                artwork: artwork,
                placedCount: $placedCount,
                placementInfo: $placementInfo,
                currentDimensions: $currentDimensions,
                surfaceMode: $surfaceMode
            )
            .ignoresSafeArea()

            // Top bar: close + title
            VStack {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(artwork.title)
                            .font(NFTTypography.headline)
                            .foregroundStyle(.white)
                        Text(artwork.artistName)
                            .font(NFTTypography.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Spacer()

                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white)
                            .shadow(radius: 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer()
            }

            // Bottom controls
            VStack(spacing: 12) {
                Spacer()

                // Dimensions indicator
                if !currentDimensions.isEmpty && placedCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "ruler")
                            .font(.caption2)
                        Text(currentDimensions)
                            .font(NFTTypography.caption)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                }

                // Placement info
                if !placementInfo.isEmpty {
                    Text(placementInfo)
                        .font(NFTTypography.caption)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .transition(.opacity)
                }

                // Hint text
                Text(placedCount > 0 ? L10n.pinchToScale : L10n.tapWallOrFloor)
                    .font(NFTTypography.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .animation(.easeInOut, value: placedCount)

                // Surface mode picker
                HStack(spacing: 0) {
                    ForEach(SurfaceMode.allCases, id: \.self) { mode in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                surfaceMode = mode
                            }
                        } label: {
                            Text(surfaceModeLabel(mode))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(surfaceMode == mode ? .white : .white.opacity(0.6))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(surfaceMode == mode ? Color.nftPurple : Color.clear)
                                .clipShape(Capsule())
                        }
                    }
                }
                .background(.ultraThinMaterial)
                .clipShape(Capsule())

                // Toolbar
                HStack(spacing: 24) {
                    toolbarButton(icon: "camera.fill", label: L10n.arTakePhoto) {
                        takeSnapshot()
                    }

                    toolbarButton(icon: "plus.rectangle.on.rectangle", label: L10n.arGalleryAdd) {
                        showGalleryPicker = true
                    }

                    if placedCount > 0 {
                        toolbarButton(icon: "trash", label: L10n.arClearAll) {
                            clearAllArtworks()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.bottom, 30)
            }
            .padding(.horizontal, 16)

            // Toast overlay
            if showToast {
                VStack {
                    Spacer()
                    Text(toastMessage)
                        .font(NFTTypography.subheadline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.green.opacity(0.85))
                        .clipShape(Capsule())
                        .padding(.bottom, 200)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .sheet(isPresented: $showGalleryPicker) {
            ArtworkPickerSheet(
                auctions: auctionService.auctions,
                selectedArtwork: .constant(nil),
                onSelect: { selected in
                    NotificationCenter.default.post(
                        name: .arGalleryAddArtwork,
                        object: selected
                    )
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .arPhotoSaved)) { notif in
            if let msg = notif.object as? String {
                showSaveToast(msg)
            }
        }
    }

    private func surfaceModeLabel(_ mode: SurfaceMode) -> String {
        switch mode {
        case .auto: return "Auto"
        case .wall: return L10n.arWallMode
        case .floor: return L10n.arFloorMode
        }
    }

    private func toolbarButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(label)
                    .font(.system(size: 10))
            }
            .foregroundStyle(.white)
            .frame(minWidth: 60)
        }
    }

    private func takeSnapshot() {
        NotificationCenter.default.post(name: .arTakeSnapshot, object: nil)
    }

    private func clearAllArtworks() {
        NotificationCenter.default.post(name: .arClearAll, object: nil)
    }

    func showSaveToast(_ message: String) {
        toastMessage = message
        withAnimation(.spring(response: 0.3)) { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showToast = false }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let arTakeSnapshot = Notification.Name("arTakeSnapshot")
    static let arClearAll = Notification.Name("arClearAll")
    static let arGalleryAddArtwork = Notification.Name("arGalleryAddArtwork")
    static let arPhotoSaved = Notification.Name("arPhotoSaved")
}

// MARK: - AR Showroom Representable

private struct ARShowroomRepresentable: UIViewRepresentable {
    let artwork: NFTArtwork
    @Binding var placedCount: Int
    @Binding var placementInfo: String
    @Binding var currentDimensions: String
    @Binding var surfaceMode: ARShowroomView.SurfaceMode

    func makeCoordinator() -> Coordinator {
        Coordinator(
            artwork: artwork,
            placedCount: $placedCount,
            placementInfo: $placementInfo,
            currentDimensions: $currentDimensions,
            surfaceMode: $surfaceMode
        )
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        guard ARWorldTrackingConfiguration.isSupported else {
            let label = UILabel()
            label.text = L10n.arNotSupported
            label.textColor = .white
            label.backgroundColor = UIColor.black.withAlphaComponent(0.7)
            label.textAlignment = .center
            label.frame = arView.bounds
            label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            arView.addSubview(label)
            return arView
        }

        // Configure AR session with horizontal + vertical plane detection
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        arView.session.run(config)

        // Coaching overlay for plane detection guidance
        let coachingOverlay = ARCoachingOverlayView()
        coachingOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        coachingOverlay.session = arView.session
        coachingOverlay.goal = .anyPlane
        coachingOverlay.activatesAutomatically = true
        arView.addSubview(coachingOverlay)

        // Tap gesture for placing artwork
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        arView.addGestureRecognizer(tapGesture)

        // Pinch gesture for scaling
        let pinchGesture = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        arView.addGestureRecognizer(pinchGesture)

        // Rotation gesture
        let rotationGesture = UIRotationGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleRotation(_:))
        )
        arView.addGestureRecognizer(rotationGesture)

        // Allow simultaneous gestures
        pinchGesture.delegate = context.coordinator
        rotationGesture.delegate = context.coordinator
        tapGesture.delegate = context.coordinator

        context.coordinator.arView = arView

        // Start preloading artwork image + USDZ model in background
        context.coordinator.preloadResources()

        // Subscribe to notification events
        context.coordinator.subscribeToNotifications()

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.surfaceMode = $surfaceMode
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        uiView.session.pause()
        coordinator.cleanup()
        uiView.scene.anchors.removeAll()
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let artwork: NFTArtwork
        var placedCount: Binding<Int>
        var placementInfo: Binding<String>
        var currentDimensions: Binding<String>
        var surfaceMode: Binding<ARShowroomView.SurfaceMode>
        weak var arView: ARView?

        // Gallery: multiple placed items
        private struct PlacedItem {
            let anchor: AnchorEntity
            let entity: Entity
            let artworkWidth: Float
            let artworkHeight: Float
            let baseOrientation: simd_quatf // stored at placement time for living painting
        }
        private var placedItems: [PlacedItem] = []
        private var selectedIndex: Int? // which placed item is selected for gestures
        private var initialScale: SIMD3<Float> = [1, 1, 1]

        // Resources
        private var usdzEntity: Entity?
        private var tempFileURL: URL?
        private var preloadedImage: UIImage?
        private var preloadedImages: [UUID: UIImage] = [:]

        // Living painting animation
        private var animationTimer: Timer?

        // Sparkle entities for "living painting" particle effect
        private var sparkleEntities: [Entity] = []

        // Notifications
        private var observers: [NSObjectProtocol] = []

        init(artwork: NFTArtwork,
             placedCount: Binding<Int>,
             placementInfo: Binding<String>,
             currentDimensions: Binding<String>,
             surfaceMode: Binding<ARShowroomView.SurfaceMode>) {
            self.artwork = artwork
            self.placedCount = placedCount
            self.placementInfo = placementInfo
            self.currentDimensions = currentDimensions
            self.surfaceMode = surfaceMode
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool { true }

        func cleanup() {
            animationTimer?.invalidate()
            animationTimer = nil
            preloadedImages.removeAll()
            sparkleEntities.removeAll()
            if let tempURL = tempFileURL {
                try? FileManager.default.removeItem(at: tempURL)
                tempFileURL = nil
            }
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers.removeAll()
        }

        // MARK: - Notifications

        func subscribeToNotifications() {
            let snapshotObs = NotificationCenter.default.addObserver(
                forName: .arTakeSnapshot, object: nil, queue: .main
            ) { [weak self] _ in
                self?.captureSnapshot()
            }
            observers.append(snapshotObs)

            let clearObs = NotificationCenter.default.addObserver(
                forName: .arClearAll, object: nil, queue: .main
            ) { [weak self] _ in
                self?.clearAll()
            }
            observers.append(clearObs)

            let galleryObs = NotificationCenter.default.addObserver(
                forName: .arGalleryAddArtwork, object: nil, queue: .main
            ) { [weak self] notif in
                guard let newArtwork = notif.object as? NFTArtwork else { return }
                self?.addGalleryArtwork(newArtwork)
            }
            observers.append(galleryObs)
        }

        // MARK: - Preload Resources

        func preloadResources() {
            Task {
                let image = await loadArtworkImageAsync(artwork)
                await MainActor.run {
                    self.preloadedImage = image
                    self.preloadedImages[artwork.id] = image
                }
            }

            guard let urlString = artwork.modelUrl, let url = URL(string: urlString) else { return }
            Task {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    let tempDir = FileManager.default.temporaryDirectory
                    let fileUrl = tempDir.appendingPathComponent("\(artwork.id.uuidString).usdz")
                    try data.write(to: fileUrl)
                    let entity = try await ModelEntity.load(contentsOf: fileUrl)
                    await MainActor.run {
                        self.tempFileURL = fileUrl
                        self.usdzEntity = entity
                    }
                } catch {}
            }
        }

        // MARK: - Tap to Place

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView = arView else { return }
            let location = gesture.location(in: arView)

            // First: try selecting an existing placed artwork via hit-test
            if let hitEntity = arView.entity(at: location) {
                if let idx = placedItems.firstIndex(where: { isDescendant(hitEntity, of: $0.entity) }) {
                    selectedIndex = idx
                    // Haptic feedback for selection
                    let generator = UISelectionFeedbackGenerator()
                    generator.selectionChanged()
                    DispatchQueue.main.async {
                        self.placementInfo.wrappedValue = L10n.arObjectSelected
                        self.updateDimensions()
                    }
                    return
                }
            }

            // Raycast chain: existingPlaneGeometry → existingPlaneInfinite → estimatedPlane
            // This 3-step chain is critical for iPhone 11 Pro (no LiDAR) — walls need
            // existingPlaneInfinite since detected geometry is often too small
            var results = arView.raycast(from: location, allowing: .existingPlaneGeometry, alignment: .any)
            var raycastQuality = "precise"
            if results.isEmpty {
                results = arView.raycast(from: location, allowing: .existingPlaneInfinite, alignment: .any)
                raycastQuality = "extended"
            }
            if results.isEmpty {
                results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any)
                raycastQuality = "estimated"
            }
            guard let firstResult = results.first else { return }

            // Determine surface type
            let isWallPlacement: Bool
            let mode = surfaceMode.wrappedValue
            switch mode {
            case .wall:
                isWallPlacement = true
            case .floor:
                isWallPlacement = false
            case .auto:
                // Check the surface normal from the raycast result
                // Column 1 (Y-axis of the plane transform) is the surface normal
                let column1 = firstResult.worldTransform.columns.1
                let surfaceNormal = SIMD3<Float>(column1.x, column1.y, column1.z)
                // For horizontal surfaces (floor/ceiling), normal.y ≈ ±1
                // For vertical surfaces (walls), normal.y ≈ 0
                isWallPlacement = abs(surfaceNormal.y) < 0.5
            }

            // Build artwork entity
            let artworkImage = preloadedImage ?? loadArtworkImageSync(artwork)
            placeArtwork(
                image: artworkImage,
                result: firstResult,
                isWall: isWallPlacement,
                raycastQuality: raycastQuality
            )
        }

        private func placeArtwork(
            image: UIImage,
            result: ARRaycastResult,
            isWall: Bool,
            raycastQuality: String
        ) {
            guard let arView = arView else { return }

            let artworkEntity: Entity
            var aw: Float = 0.5
            var ah: Float = 0.5

            if let usdz = usdzEntity?.clone(recursive: true) {
                let bounds = usdz.visualBounds(relativeTo: nil)
                let extent = bounds.extents
                let maxDimension = max(extent.x, max(extent.y, extent.z))
                let targetSize: Float = 0.5
                let scaleFactor = maxDimension > 0 ? targetSize / maxDimension : 1.0
                usdz.scale = [scaleFactor, scaleFactor, scaleFactor]
                aw = extent.x * scaleFactor
                ah = extent.y * scaleFactor
                if !isWall {
                    usdz.position.y = -bounds.min.y * scaleFactor
                }
                artworkEntity = usdz
            } else {
                let (entity, width, height) = createFramedArtwork(image: image, isWall: isWall)
                artworkEntity = entity
                aw = width
                ah = height
            }

            // Create anchor
            let anchor: AnchorEntity
            if isWall {
                // Wall: use the full raycast transform (includes wall orientation)
                anchor = AnchorEntity(world: result.worldTransform)
            } else {
                // Floor: use only position, then orient artwork to face camera
                let position = result.worldTransform.columns.3
                var transform = matrix_identity_float4x4
                transform.columns.3 = position
                anchor = AnchorEntity(world: transform)

                // Rotate artwork to face the camera
                if let cameraTransform = arView.session.currentFrame?.camera.transform {
                    let cameraPos = SIMD3<Float>(
                        cameraTransform.columns.3.x,
                        cameraTransform.columns.3.y,
                        cameraTransform.columns.3.z
                    )
                    let artworkPos = SIMD3<Float>(position.x, position.y, position.z)
                    let direction = cameraPos - artworkPos
                    let angle = atan2(direction.x, direction.z)
                    artworkEntity.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
                }
            }

            anchor.addChild(artworkEntity)

            // Add museum spotlight with "living painting" animation
            addSpotlight(to: anchor, isWall: isWall, artworkWidth: aw, artworkHeight: ah)

            // Add sparkle particles around frame
            addSparkles(to: anchor, width: aw, height: ah, isWall: isWall)

            arView.scene.addAnchor(anchor)

            let item = PlacedItem(
                anchor: anchor,
                entity: artworkEntity,
                artworkWidth: aw,
                artworkHeight: ah,
                baseOrientation: artworkEntity.orientation
            )
            placedItems.append(item)
            selectedIndex = placedItems.count - 1
            initialScale = artworkEntity.scale

            // Start living painting animation if first placement
            if placedItems.count == 1 {
                startLivingPaintingAnimation()
            }

            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            let surface = isWall ? "wall" : "floor"
            MetricsService.shared.trackARPlacement(surface: surface)

            DispatchQueue.main.async {
                self.placedCount.wrappedValue = self.placedItems.count
                let qualityHint = raycastQuality == "estimated" ? " ~" : ""
                self.placementInfo.wrappedValue = (isWall
                    ? L10n.placedOnWall
                    : L10n.placedOnFloor) + qualityHint
                self.updateDimensions()
            }
        }

        private func isDescendant(_ entity: Entity, of ancestor: Entity) -> Bool {
            var current: Entity? = entity
            while let e = current {
                if e === ancestor { return true }
                current = e.parent
            }
            return false
        }

        // MARK: - Pinch to Scale

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let idx = selectedIndex, idx < placedItems.count else { return }
            let entity = placedItems[idx].entity

            switch gesture.state {
            case .began:
                initialScale = entity.scale
            case .changed:
                let scale = Float(gesture.scale)
                let clamped = min(max(scale, 0.2), 5.0)
                entity.scale = initialScale * clamped
                DispatchQueue.main.async { self.updateDimensions() }
            default:
                break
            }
        }

        // MARK: - Rotation

        @objc func handleRotation(_ gesture: UIRotationGestureRecognizer) {
            guard let idx = selectedIndex, idx < placedItems.count else { return }
            let entity = placedItems[idx].entity

            switch gesture.state {
            case .changed:
                let rotation = simd_quatf(angle: -Float(gesture.rotation), axis: [0, 1, 0])
                entity.orientation = entity.orientation * rotation
                gesture.rotation = 0
                // Update base orientation after manual rotation
                placedItems[idx] = PlacedItem(
                    anchor: placedItems[idx].anchor,
                    entity: entity,
                    artworkWidth: placedItems[idx].artworkWidth,
                    artworkHeight: placedItems[idx].artworkHeight,
                    baseOrientation: entity.orientation
                )
            default:
                break
            }
        }

        // MARK: - Dimension Indicator

        private func updateDimensions() {
            guard let idx = selectedIndex, idx < placedItems.count else { return }
            let item = placedItems[idx]
            let scale = item.entity.scale.x
            let widthCm = Int(item.artworkWidth * scale * 100)
            let heightCm = Int(item.artworkHeight * scale * 100)
            currentDimensions.wrappedValue = "\(widthCm) × \(heightCm) " + L10n.arDimensions
        }

        // MARK: - Create Framed Artwork

        private func createFramedArtwork(image: UIImage, isWall: Bool) -> (Entity, Float, Float) {
            let parentEntity = Entity()

            let aspectRatio = image.size.width / image.size.height
            let maxSize: Float = 0.5
            let artworkWidth: Float
            let artworkHeight: Float
            if aspectRatio >= 1 {
                artworkWidth = maxSize
                artworkHeight = maxSize / Float(aspectRatio)
            } else {
                artworkHeight = maxSize
                artworkWidth = maxSize * Float(aspectRatio)
            }

            let frameThickness: Float = 0.02
            let frameDepth: Float = 0.025
            let totalWidth = artworkWidth + frameThickness * 2
            let totalHeight = artworkHeight + frameThickness * 2

            // --- Frame bars (boxes in XY plane) ---
            var frameMaterial = SimpleMaterial()
            frameMaterial.color = .init(tint: UIColor(red: 0.2, green: 0.15, blue: 0.1, alpha: 1.0))
            frameMaterial.metallic = .float(0.3)
            frameMaterial.roughness = .float(0.6)

            let bars: [(Float, Float, SIMD3<Float>)] = [
                (totalWidth, frameThickness, [0, (artworkHeight + frameThickness) / 2, 0]),
                (totalWidth, frameThickness, [0, -(artworkHeight + frameThickness) / 2, 0]),
                (frameThickness, artworkHeight, [-(artworkWidth + frameThickness) / 2, 0, 0]),
                (frameThickness, artworkHeight, [(artworkWidth + frameThickness) / 2, 0, 0]),
            ]

            for (w, h, pos) in bars {
                let barMesh = MeshResource.generateBox(width: w, height: h, depth: frameDepth, cornerRadius: 0.002)
                let barEntity = ModelEntity(mesh: barMesh, materials: [frameMaterial])
                barEntity.position = pos
                parentEntity.addChild(barEntity)
            }

            // --- Canvas backing ---
            let matMargin: Float = 0.01
            let matMesh = MeshResource.generateBox(
                width: artworkWidth + matMargin * 2,
                height: artworkHeight + matMargin * 2,
                depth: 0.003
            )
            var matMaterial = SimpleMaterial()
            matMaterial.color = .init(tint: UIColor(white: 0.95, alpha: 1.0))
            matMaterial.roughness = .float(0.9)
            let matEntity = ModelEntity(mesh: matMesh, materials: [matMaterial])
            matEntity.position = [0, 0, -frameDepth / 2 + 0.002]
            parentEntity.addChild(matEntity)

            // --- Artwork image ---
            // generateBox(width:height:depth:) creates mesh in XY plane — always vertical
            let artworkMesh = MeshResource.generateBox(
                width: artworkWidth,
                height: artworkHeight,
                depth: 0.001
            )
            var artworkMaterial = UnlitMaterial()
            if let cgImage = image.cgImage,
               let texture = try? TextureResource.generate(
                   from: cgImage,
                   options: .init(semantic: .color)
               ) {
                artworkMaterial.color = .init(tint: .white, texture: .init(texture))
            }

            let artworkEntity = ModelEntity(mesh: artworkMesh, materials: [artworkMaterial])
            artworkEntity.position = [0, 0, frameDepth / 2 + 0.001]
            parentEntity.addChild(artworkEntity)

            // --- Position the entire group ---
            if isWall {
                // Wall: anchor already has wall orientation from raycast transform
                // Just push artwork slightly away from wall surface along local Z
                parentEntity.position.z = frameDepth / 2 + 0.005
            } else {
                // Floor: artwork is already in XY plane (vertical) thanks to generateBox
                // NO rotation needed — just lift above the floor
                parentEntity.position.y = totalHeight / 2 + 0.01
            }

            return (parentEntity, artworkWidth, artworkHeight)
        }

        // MARK: - Museum Spotlight (scaled to artwork size)

        private func addSpotlight(to anchor: AnchorEntity, isWall: Bool, artworkWidth: Float, artworkHeight: Float) {
            let spotLight = SpotLight()
            spotLight.light.color = UIColor(white: 1.0, alpha: 1.0)
            spotLight.light.intensity = 3000
            spotLight.light.innerAngleInDegrees = 30
            spotLight.light.outerAngleInDegrees = 50
            spotLight.light.attenuationRadius = 3.0
            spotLight.name = "museumSpotlight"

            // Scale spotlight distance based on artwork size
            let artSize = max(artworkWidth, artworkHeight)
            let spotDistance = artSize + 0.3

            if isWall {
                spotLight.position = [0, spotDistance * 0.8, spotDistance * 0.6]
                spotLight.look(at: [0, 0, 0], from: spotLight.position, relativeTo: anchor)
            } else {
                spotLight.position = [0, spotDistance * 1.2, spotDistance * 0.4]
                spotLight.look(at: [0, artSize * 0.5, 0], from: spotLight.position, relativeTo: anchor)
            }
            anchor.addChild(spotLight)

            // Soft ambient fill
            let pointLight = PointLight()
            pointLight.light.color = UIColor(white: 0.9, alpha: 1.0)
            pointLight.light.intensity = 500
            pointLight.light.attenuationRadius = 2.0
            pointLight.position = isWall ? [0, 0, spotDistance * 0.8] : [0, artSize * 0.8, spotDistance * 0.7]
            pointLight.name = "ambientFill"
            anchor.addChild(pointLight)
        }

        // MARK: - Sparkle Particles (CosmoDreams: "living paintings")

        private func addSparkles(to anchor: AnchorEntity, width: Float, height: Float, isWall: Bool) {
            let sparkleCount = 8
            for i in 0..<sparkleCount {
                let size: Float = 0.004
                let mesh = MeshResource.generateSphere(radius: size)
                var material = UnlitMaterial()
                let hue = CGFloat(i) / CGFloat(sparkleCount)
                material.color = .init(
                    tint: UIColor(hue: hue, saturation: 0.3, brightness: 1.0, alpha: 0.6)
                )
                let sparkle = ModelEntity(mesh: mesh, materials: [material])
                sparkle.name = "sparkle_\(i)"

                // Position around frame perimeter
                let t = Float(i) / Float(sparkleCount)
                let perimeter = 2 * (width + height)
                let dist = t * perimeter
                var x: Float = 0
                var y: Float = 0
                let hw = width / 2 + 0.03
                let hh = height / 2 + 0.03
                if dist < width {
                    x = -hw + dist / width * (hw * 2)
                    y = hh
                } else if dist < width + height {
                    x = hw
                    y = hh - (dist - width) / height * (hh * 2)
                } else if dist < width * 2 + height {
                    x = hw - (dist - width - height) / width * (hw * 2)
                    y = -hh
                } else {
                    x = -hw
                    y = -hh + (dist - width * 2 - height) / height * (hh * 2)
                }

                if isWall {
                    sparkle.position = [x, y, 0.02]
                } else {
                    sparkle.position = [x, 0.02, -y]
                }

                anchor.addChild(sparkle)
                sparkleEntities.append(sparkle)
            }
        }

        // MARK: - Living Painting Animation (FIX: uses stored base orientation)

        private func startLivingPaintingAnimation() {
            var phase: Float = 0
            animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                phase += 0.02

                for item in self.placedItems {
                    // Pulsating spotlight intensity (2500-3500)
                    let spotlightIntensity: Float = 3000 + 500 * sin(phase)
                    let fillIntensity: Float = 500 + 150 * sin(phase * 0.7 + 1.0)

                    item.anchor.children.forEach { child in
                        if child.name == "museumSpotlight", let spot = child as? SpotLight {
                            spot.light.intensity = spotlightIntensity
                        }
                        if child.name == "ambientFill", let point = child as? PointLight {
                            point.light.intensity = fillIntensity
                        }
                    }

                    // Gentle sway — FIX: use STORED base orientation, not current
                    let swayAngle = 0.003 * sin(phase * 0.5)
                    let tiltAngle = 0.002 * sin(phase * 0.3 + 0.5)
                    let sway = simd_quatf(angle: swayAngle, axis: [0, 1, 0])
                    let tilt = simd_quatf(angle: tiltAngle, axis: [1, 0, 0])
                    item.entity.orientation = item.baseOrientation * sway * tilt
                }

                // Animate sparkle particles — orbit and fade
                for (i, sparkle) in self.sparkleEntities.enumerated() {
                    let offset = Float(i) * 0.8
                    let pulse = 0.5 + 0.5 * sin(phase * 1.5 + offset)
                    let scale = 0.5 + pulse * 1.0
                    sparkle.scale = [scale, scale, scale]

                    // Gentle float
                    let basePos = sparkle.position
                    let floatY: Float = 0.005 * sin(phase * 0.8 + offset)
                    let floatX: Float = 0.003 * sin(phase * 0.6 + offset * 1.3)
                    sparkle.position = [
                        basePos.x + floatX * 0.01,
                        basePos.y + floatY * 0.01,
                        basePos.z
                    ]
                }
            }
        }

        // MARK: - Photo Capture

        private func captureSnapshot() {
            guard let arView = arView else { return }

            // Flash effect
            let flashView = UIView(frame: arView.bounds)
            flashView.backgroundColor = .white
            flashView.alpha = 0
            arView.addSubview(flashView)
            UIView.animate(withDuration: 0.1, animations: {
                flashView.alpha = 0.7
            }) { _ in
                UIView.animate(withDuration: 0.2, animations: {
                    flashView.alpha = 0
                }) { _ in
                    flashView.removeFromSuperview()
                }
            }

            arView.snapshot(saveToHDR: false) { image in
                guard let image = image else { return }

                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    guard status == .authorized || status == .limited else {
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: .arPhotoSaved,
                                object: L10n.arPhotoNoPermission
                            )
                        }
                        return
                    }

                    PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.creationRequestForAsset(from: image)
                    } completionHandler: { success, _ in
                        DispatchQueue.main.async {
                            let msg = success ? L10n.arPhotoSaved : "Error"
                            NotificationCenter.default.post(name: .arPhotoSaved, object: msg)
                            if success {
                                let generator = UINotificationFeedbackGenerator()
                                generator.notificationOccurred(.success)
                            }
                        }
                    }
                }
            }
        }

        // MARK: - Gallery: Add Another Artwork

        private func addGalleryArtwork(_ newArtwork: NFTArtwork) {
            guard placedItems.count < 10 else {
                DispatchQueue.main.async {
                    self.placementInfo.wrappedValue = "Max 10"
                }
                return
            }

            Task {
                let image = await loadArtworkImageAsync(newArtwork)
                await MainActor.run {
                    self.preloadedImages[newArtwork.id] = image
                    self.placeInFrontOfCamera(artwork: newArtwork, image: image)
                }
            }
        }

        private func placeInFrontOfCamera(artwork: NFTArtwork, image: UIImage) {
            guard let arView = arView,
                  let cameraTransform = arView.session.currentFrame?.camera.transform else {
                DispatchQueue.main.async {
                    self.placementInfo.wrappedValue = "Tracking lost"
                }
                return
            }

            // Place 1m in front of camera
            let forward = cameraTransform.columns.2
            let position = cameraTransform.columns.3
            let placementPosition = SIMD3<Float>(
                position.x - forward.x * 1.0,
                position.y - forward.y * 1.0,
                position.z - forward.z * 1.0
            )

            let (entity, aw, ah) = createFramedArtwork(image: image, isWall: true)

            var transform = matrix_identity_float4x4
            transform.columns.3 = SIMD4<Float>(placementPosition.x, placementPosition.y, placementPosition.z, 1)
            let anchor = AnchorEntity(world: transform)

            // Face toward camera
            let cameraPos = SIMD3<Float>(position.x, position.y, position.z)
            let direction = cameraPos - placementPosition
            let angle = atan2(direction.x, direction.z)
            entity.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])

            anchor.addChild(entity)
            addSpotlight(to: anchor, isWall: true, artworkWidth: aw, artworkHeight: ah)
            addSparkles(to: anchor, width: aw, height: ah, isWall: true)
            arView.scene.addAnchor(anchor)

            let item = PlacedItem(
                anchor: anchor,
                entity: entity,
                artworkWidth: aw,
                artworkHeight: ah,
                baseOrientation: entity.orientation
            )
            placedItems.append(item)
            selectedIndex = placedItems.count - 1
            initialScale = entity.scale

            // Haptic
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()

            DispatchQueue.main.async {
                self.placedCount.wrappedValue = self.placedItems.count
                self.placementInfo.wrappedValue = L10n.arGalleryAdd + " (\(self.placedItems.count))"
                self.updateDimensions()
            }
        }

        // MARK: - Clear All

        private func clearAll() {
            guard let arView = arView else { return }
            for item in placedItems {
                arView.scene.removeAnchor(item.anchor)
            }
            placedItems.removeAll()
            sparkleEntities.removeAll()
            selectedIndex = nil
            animationTimer?.invalidate()
            animationTimer = nil

            // Haptic
            let generator = UIImpactFeedbackGenerator(style: .rigid)
            generator.impactOccurred()

            DispatchQueue.main.async {
                self.placedCount.wrappedValue = 0
                self.placementInfo.wrappedValue = ""
                self.currentDimensions.wrappedValue = ""
            }
        }

        // MARK: - Image Loading

        private func loadArtworkImageAsync(_ art: NFTArtwork) async -> UIImage {
            if art.imageSource == .uploaded,
               let data = art.localImageData,
               let img = UIImage(data: data) {
                return img
            }
            if art.imageSource == .bundled,
               let img = UIImage(named: art.imageName) {
                return img
            }
            if art.imageSource == .url,
               let urlString = art.imageURL,
               let url = URL(string: urlString) {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    if let img = UIImage(data: data) { return img }
                } catch {}
            }
            return MockDataService.generateArtworkImage(
                for: art,
                size: CGSize(width: 512, height: 512)
            )
        }

        private func loadArtworkImageSync(_ art: NFTArtwork) -> UIImage {
            if let cached = preloadedImages[art.id] { return cached }
            if art.imageSource == .uploaded,
               let data = art.localImageData,
               let img = UIImage(data: data) {
                return img
            }
            if art.imageSource == .bundled,
               let img = UIImage(named: art.imageName) {
                return img
            }
            if art.imageSource == .url,
               let urlString = art.imageURL,
               let url = URL(string: urlString),
               let data = try? Data(contentsOf: url),
               let img = UIImage(data: data) {
                return img
            }
            return MockDataService.generateArtworkImage(
                for: art,
                size: CGSize(width: 512, height: 512)
            )
        }
    }
}
