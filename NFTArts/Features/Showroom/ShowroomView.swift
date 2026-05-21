import SwiftUI
import SceneKit

/// Full-screen 3D virtual showroom: walks the user through a room with their collection.
/// Camera modes: orbit (turntable around centre) and walk (free fly with eye-level start).
/// Tap on a painting opens its detail card.
struct ShowroomView: View {
    let artworks: [NFTArtwork]
    let collectionName: String
    var collectionId: UUID?
    @EnvironmentObject var auctionService: AuctionService

    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = ShowroomController()
    @State private var showHint = true
    @State private var scene: SCNScene?
    @AppStorage("showroom_theme") private var themeRaw: String = ShowroomTheme.louvre.rawValue
    @AppStorage("showroom_lighting") private var lightingRaw: String = LightingMode.gallery.rawValue
    @State private var tappedPainting: PaintingTap?
    @State private var rearrangeMode: Bool = false
    @State private var firstSelectedId: UUID?
    @State private var paintingOrder: [UUID] = []
    @State private var showResetConfirm: Bool = false
    @State private var transientToast: String?

    private var theme: ShowroomTheme {
        ShowroomTheme(rawValue: themeRaw) ?? .louvre
    }
    private var lighting: LightingMode {
        LightingMode(rawValue: lightingRaw) ?? .gallery
    }

    /// Камера в шоуруме только orbit (юзер статичный, сцена вращается вокруг центра).
    /// Walk-режим убран — оказался дезориентирующим (отзыв 2026-05-19).
    enum CameraMode {
        case orbit
        // .fly = drag вращает обзор без перемещения камеры (юзер статичен в центре зала).
        // .orbitTurntable пытается двигать камеру по орбите вокруг target — для нашего
        // кейса "юзер в центре" это не подходит.
        var sceneKitMode: SCNInteractionMode { .fly }
    }

    /// Modifier поверх палитры темы — даёт юзеру переключать освещение.
    enum LightingMode: String, CaseIterable {
        case gallery, day, night
        var icon: String {
            switch self {
            case .gallery: return "lightbulb.fill"
            case .day:     return "sun.max.fill"
            case .night:   return "moon.fill"
            }
        }
        var next: LightingMode {
            switch self {
            case .gallery: return .day
            case .day:     return .night
            case .night:   return .gallery
            }
        }
    }

    /// Identifiable wrapper so we can use `.fullScreenCover(item:)`.
    struct PaintingTap: Identifiable {
        let id: UUID
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let scene {
                SceneKitContainer(
                    controller: controller,
                    scene: scene,
                    cameraMode: .orbit,
                    onPaintingTapped: handlePaintingTap
                )
                .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
            }

            VStack {
                topBar
                if rearrangeMode {
                    rearrangeBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
                if !rearrangeMode {
                    orbitPad.transition(.opacity)
                }
                if let toast = transientToast {
                    Text(toast)
                        .font(NFTTypography.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.7), in: Capsule())
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 12)
                }
                if showHint && !rearrangeMode {
                    hintBar
                        .transition(.opacity)
                }
            }
        }
        .alert(L10n.showroomResetLayout, isPresented: $showResetConfirm) {
            Button(L10n.cancel, role: .cancel) {}
            Button(L10n.delete, role: .destructive) {
                ShowroomLayoutStore.reset(collectionId: collectionId)
                rebuildScene()
            }
        }
        .statusBarHidden()
        .task {
            await buildScene()
        }
        .fullScreenCover(item: $tappedPainting) { tap in
            if let auction = auctionService.auctions.first(where: { $0.artwork.id == tap.id }) {
                NavigationStack {
                    ArtworkDetailView(auction: auction)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button(L10n.cancel) { tappedPainting = nil }
                            }
                        }
                }
                .environmentObject(auctionService)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                iconButton("xmark")
            }
            Spacer()
            VStack(spacing: 2) {
                Text(L10n.showroom)
                    .font(NFTTypography.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Text(collectionName)
                    .font(NFTTypography.title2)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer()
            Menu {
                ForEach(ShowroomTheme.allCases) { option in
                    Button {
                        HapticService.light()
                        themeRaw = option.rawValue
                        rebuildScene()
                        showToast(option.displayName)
                    } label: {
                        if option == theme {
                            Label(option.displayName, systemImage: "checkmark")
                        } else {
                            Label(option.displayName, systemImage: option.icon)
                        }
                    }
                }
            } label: {
                iconButton(theme.icon)
            }
            Button {
                HapticService.light()
                lightingRaw = lighting.next.rawValue
                controller.applyLighting(lighting, themePalette: theme.palette)
            } label: {
                iconButton(lighting.icon)
            }
            Button {
                HapticService.tap()
                controller.recenter()
            } label: {
                iconButton("scope")
            }
            Menu {
                Button {
                    HapticService.tap()
                    withAnimation(.spring(response: 0.35)) {
                        rearrangeMode = true
                    }
                    firstSelectedId = nil
                    controller.setHighlight(nil)
                } label: {
                    Label(L10n.showroomArrangePaintings, systemImage: "rectangle.3.group")
                }
                Button(role: .destructive) {
                    HapticService.warning()
                    showResetConfirm = true
                } label: {
                    Label(L10n.showroomResetLayout, systemImage: "arrow.counterclockwise")
                }
            } label: {
                iconButton("slider.horizontal.3")
            }
        }
        .padding()
    }

    private var rearrangeBanner: some View {
        let hint = firstSelectedId == nil ? L10n.showroomArrangeHint1 : L10n.showroomArrangeHint2
        return HStack(spacing: 12) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.nftPurple)
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.showroomArrangePaintings)
                    .font(NFTTypography.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                Text(hint)
                    .font(NFTTypography.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
            Button {
                HapticService.tap()
                withAnimation(.spring(response: 0.35)) {
                    rearrangeMode = false
                }
                firstSelectedId = nil
                controller.setHighlight(nil)
            } label: {
                Text(L10n.showroomArrangeDone)
                    .font(NFTTypography.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.nftPurple, in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 12)
    }

    /// Кнопки управления orbit-камерой — юзер стоит в центре и крутит обзор.
    /// Вверх/вниз = зум, влево/вправо = вращение вокруг центра.
    private var orbitPad: some View {
        VStack(spacing: 6) {
            orbitButton("plus.magnifyingglass", action: { controller.orbit(.zoomIn) })
            HStack(spacing: 6) {
                orbitButton("arrow.turn.up.left", action: { controller.orbit(.rotateLeft) })
                orbitButton("minus.magnifyingglass", action: { controller.orbit(.zoomOut) })
                orbitButton("arrow.turn.up.right", action: { controller.orbit(.rotateRight) })
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.bottom, 80)
    }

    private func orbitButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticService.light()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(.black.opacity(0.35), in: Circle())
        }
    }

    private func iconButton(_ system: String) -> some View {
        Image(systemName: system)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(.ultraThinMaterial, in: Circle())
    }

    private var hintBar: some View {
        HStack(spacing: 16) {
            if rearrangeMode {
                Label(L10n.showroomHintLongPress, systemImage: "rectangle.3.group")
            } else {
                Label(L10n.showroomHintDrag, systemImage: "hand.draw")
                Label(L10n.showroomHintTap, systemImage: "hand.tap")
            }
        }
        .font(NFTTypography.caption)
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 24)
        .task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            withAnimation { showHint = false }
        }
    }

    private func handlePaintingTap(_ id: UUID) {
        if rearrangeMode {
            HapticService.tap()
            if let first = firstSelectedId {
                if first == id {
                    firstSelectedId = nil
                    controller.setHighlight(nil)
                    return
                }
                controller.swap(firstId: first, secondId: id)
                if let i = paintingOrder.firstIndex(of: first),
                   let j = paintingOrder.firstIndex(of: id) {
                    paintingOrder.swapAt(i, j)
                    ShowroomLayoutStore.save(order: paintingOrder, collectionId: collectionId)
                }
                firstSelectedId = nil
                controller.setHighlight(nil)
                showToast(L10n.showroomLayoutSaved)
            } else {
                firstSelectedId = id
                controller.setHighlight(id)
            }
        } else {
            HapticService.medium()
            tappedPainting = PaintingTap(id: id)
        }
    }

    private func showToast(_ message: String) {
        withAnimation(.spring(response: 0.3)) { transientToast = message }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation { transientToast = nil }
        }
    }

    private func rebuildScene() {
        firstSelectedId = nil
        controller.setHighlight(nil)
        Task { await buildScene() }
    }

    private func buildScene() async {
        let ordered = ShowroomLayoutStore.ordered(artworks, collectionId: collectionId)
        let snapshot = ordered
        let currentTheme = theme
        paintingOrder = snapshot.map(\.id)
        let scene = await Task.detached(priority: .userInitiated) {
            ShowroomSceneBuilder.build(artworks: snapshot, theme: currentTheme)
        }.value
        self.scene = scene
        AnalyticsService.shared.track(.showroomOpened, parameters: ["count": snapshot.count, "theme": currentTheme.rawValue])
    }
}

// MARK: - Controller

@MainActor
final class ShowroomController: ObservableObject {
    weak var scnView: SCNView?

    enum OrbitAction { case rotateLeft, rotateRight, zoomIn, zoomOut }

    /// Юзер стоит в центре зала и вращает обзор по yaw — точно как осматриваться вокруг.
    /// Никаких look(at:) на пивот: куда повернул — туда и смотришь.
    func orbit(_ action: OrbitAction) {
        guard let pov = scnView?.pointOfView else { return }
        switch action {
        case .rotateLeft, .rotateRight:
            let delta: CGFloat = (action == .rotateLeft) ? .pi / 12 : -.pi / 12 // ~15°
            let rotate = SCNAction.rotateBy(x: 0, y: delta, z: 0, duration: 0.25)
            rotate.timingMode = .easeInEaseOut
            pov.runAction(rotate)
        case .zoomIn, .zoomOut:
            // Зум через field-of-view камеры — юзер физически остаётся на месте,
            // но картина приближается/отдаляется визуально.
            guard let camera = pov.camera else { return }
            let step: CGFloat = (action == .zoomIn) ? -8 : 8
            let target = min(max(camera.fieldOfView + step, 25), 90)
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.25
            camera.fieldOfView = target
            SCNTransaction.commit()
        }
    }

    /// Возвращает в стартовое положение: камера в центре, смотрит на север, FOV дефолтный.
    func recenter() {
        guard let pov = scnView?.pointOfView else { return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.4
        pov.position = SCNVector3(0, 1.7, 0)
        pov.eulerAngles = SCNVector3(0, 0, 0)
        pov.camera?.fieldOfView = 65
        SCNTransaction.commit()
    }

    /// Применяет лайтинг-модификатор поверх палитры темы.
    /// gallery — палитра темы as-is; day — поднимаем ambient, day-light; night — гасим всё, accent на картины.
    func applyLighting(_ mode: ShowroomView.LightingMode, themePalette: ShowroomTheme.Palette) {
        guard let scene = scnView?.scene else { return }
        ShowroomSceneBuilder.applyLighting(mode, themePalette: themePalette, to: scene)
    }

    /// Swaps the wall positions of two paintings in-place (no scene rebuild).
    func swap(firstId: UUID, secondId: UUID) {
        guard let scene = scnView?.scene else { return }
        guard let a = scene.rootNode.childNode(withName: "painting_\(firstId.uuidString)", recursively: true),
              let b = scene.rootNode.childNode(withName: "painting_\(secondId.uuidString)", recursively: true)
        else { return }

        let moveDuration: TimeInterval = 0.45
        let aTarget = b.position
        let bTarget = a.position
        let aRot = b.eulerAngles
        let bRot = a.eulerAngles

        a.runAction(SCNAction.group([
            SCNAction.move(to: aTarget, duration: moveDuration),
            SCNAction.rotateTo(x: CGFloat(aRot.x), y: CGFloat(aRot.y), z: CGFloat(aRot.z), duration: moveDuration)
        ]))
        b.runAction(SCNAction.group([
            SCNAction.move(to: bTarget, duration: moveDuration),
            SCNAction.rotateTo(x: CGFloat(bRot.x), y: CGFloat(bRot.y), z: CGFloat(bRot.z), duration: moveDuration)
        ]))
    }

    /// Visually highlights a painting (used when selecting the first item to swap).
    /// Pass nil to clear all highlights.
    func setHighlight(_ paintingId: UUID?) {
        guard let scene = scnView?.scene else { return }
        scene.rootNode.enumerateChildNodes { node, _ in
            guard let name = node.name, name.hasPrefix("painting_") else { return }
            let isSelected = paintingId.map { "painting_\($0.uuidString)" == name } ?? false
            let targetScale: Float = isSelected ? 1.08 : 1.0
            node.runAction(SCNAction.scale(to: CGFloat(targetScale), duration: 0.2))
        }
    }
}

// MARK: - SceneKit container with tap handling

private struct SceneKitContainer: UIViewRepresentable {
    let controller: ShowroomController
    let scene: SCNScene
    let cameraMode: ShowroomView.CameraMode
    let onPaintingTapped: (UUID) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onPaintingTapped)
    }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .black
        scnView.antialiasingMode = .multisampling4X
        scnView.allowsCameraControl = true
        scnView.defaultCameraController.interactionMode = cameraMode.sceneKitMode
        scnView.defaultCameraController.maximumVerticalAngle = 35
        scnView.defaultCameraController.minimumVerticalAngle = -10
        scnView.scene = scene

        // Tap-to-detail: hit test through SCNView, walk up to find the painting node.
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        scnView.addGestureRecognizer(tap)
        context.coordinator.scnView = scnView
        controller.scnView = scnView
        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        if uiView.scene !== scene {
            uiView.scene = scene
        }
        uiView.defaultCameraController.interactionMode = cameraMode.sceneKitMode
        context.coordinator.onTap = onPaintingTapped
    }

    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) {
        uiView.scene?.rootNode.enumerateChildNodes { node, _ in
            node.geometry?.materials.forEach { material in
                material.diffuse.contents = nil
                material.normal.contents = nil
                material.displacement.contents = nil
            }
            node.light = nil
        }
        uiView.scene = nil
        uiView.pointOfView = nil
        coordinator.scnView = nil
    }

    final class Coordinator: NSObject {
        weak var scnView: SCNView?
        var onTap: (UUID) -> Void

        init(onTap: @escaping (UUID) -> Void) {
            self.onTap = onTap
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let scnView else { return }
            let location = gesture.location(in: scnView)
            let hits = scnView.hitTest(location, options: [
                SCNHitTestOption.boundingBoxOnly: false,
                SCNHitTestOption.searchMode: SCNHitTestSearchMode.closest.rawValue
            ])
            for hit in hits {
                var node: SCNNode? = hit.node
                while let n = node {
                    if let name = n.name, name.hasPrefix("painting_") {
                        let uuidStr = String(name.dropFirst("painting_".count))
                        if let uuid = UUID(uuidString: uuidStr) {
                            onTap(uuid)
                        }
                        return
                    }
                    node = n.parent
                }
            }
        }
    }
}
