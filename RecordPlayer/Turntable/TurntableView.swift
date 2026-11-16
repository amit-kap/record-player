import RealityKit
import SwiftUI
import TurntableCore

/// The turntable seen from above. Drag the tonearm or press the buttons on the plinth.
struct TurntableView: View {
    let model: TurntableModel
    var theme: TurntableTheme = .dark
    var cameraView: TurntableCameraView = .top
    /// Camera poses the user has adjusted, by view.
    var adjustedPoses: [TurntableCameraView: CameraPose] = [:]

    @State private var scene: TurntableScene?
    @State private var frameUpdates: EventSubscription?
    @State private var dragStarted: Bool?
    @State private var focus = FocusSettings()

    var body: some View {
        GeometryReader { proxy in
            RealityView { content in
                guard let scene = try? await TurntableScene(
                    spec: model.spec, theme: theme, trackStarts: model.trackStarts
                ) else {
                    return
                }
                content.camera = .virtual
                content.renderingEffects.antialiasing = .multisample4X
                if #available(macOS 26.0, *) {
                    content.renderingEffects.customPostProcessing = .effect(DepthOfFieldEffect(focus: focus))
                }
                content.add(scene.root)
                frameUpdates = content.subscribe(to: SceneEvents.Update.self) { event in
                    MainActor.assumeIsolated {
                        scene.update(deltaTime: Float(event.deltaTime), model: model)
                        focus.set(distance: scene.focusDistance, blur: scene.blur)
                    }
                }
                scene.adjustedPoses = adjustedPoses
                scene.show(cameraView, in: proxy.size, animated: false)
                self.scene = scene
            } update: { _ in
                scene?.show(cameraView, in: proxy.size)
            }
            .gesture(press(in: proxy.size))
            .onChange(of: cameraView) { scene?.show(cameraView, in: proxy.size) }
            .onChange(of: adjustedPoses) { scene?.adjustedPoses = adjustedPoses }
            .onChange(of: proxy.size) { scene?.show(cameraView, in: proxy.size) }
        }
        .background(.black)
        .ignoresSafeArea()
    }

    /// One gesture for the tonearm and the buttons, read through the camera as it is placed right now, so it
    /// works from every view.
    private func press(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let scene else { return }
                let spec = model.spec
                let onArmPlane = scene.sceneCamera.tablePoint(
                    for: value.location, in: size, planeHeight: spec.armGrabHeight
                )
                if dragStarted == nil {
                    let onArm = onArmPlane.map { model.beginDrag(at: $0, currentSwing: scene.currentSwing) } ?? false
                    dragStarted = onArm
                    if !onArm, let point = scene.sceneCamera.tablePoint(
                        for: value.location, in: size, planeHeight: spec.buttonHeight
                    ) {
                        model.press(at: point)
                    }
                }
                if dragStarted == true, let onArmPlane {
                    model.drag(to: onArmPlane)
                }
            }
            .onEnded { value in
                if dragStarted == true {
                    model.endDrag()
                } else if let scene, let point = scene.sceneCamera.tablePoint(
                    for: value.location, in: size, planeHeight: model.spec.buttonHeight
                ) {
                    model.release(at: point)
                } else {
                    model.cancelPress()
                }
                dragStarted = nil
            }
    }
}
