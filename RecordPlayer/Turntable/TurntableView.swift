import RealityKit
import SwiftUI
import TurntableCore

/// The turntable seen from above. Drag the tonearm or press the buttons on the plinth.
struct TurntableView: View {
    let model: TurntableModel
    var theme: TurntableTheme = .dark
    /// Width kept clear of the turntable on the trailing side, for controls.
    var trailingInset: CGFloat = 0

    @State private var scene: TurntableScene?
    @State private var frameUpdates: EventSubscription?
    @State private var dragStarted: Bool?

    var body: some View {
        GeometryReader { proxy in
            let camera = camera(for: proxy.size)
            RealityView { content in
                guard let scene = try? await TurntableScene(geometry: model.geometry, theme: theme) else {
                    return
                }
                content.camera = .virtual
                content.add(scene.root)
                frameUpdates = content.subscribe(to: SceneEvents.Update.self) { event in
                    MainActor.assumeIsolated {
                        scene.update(deltaTime: Float(event.deltaTime), model: model)
                    }
                }
                scene.place(camera: camera)
                self.scene = scene
            } update: { _ in
                scene?.place(camera: camera)
            }
            .gesture(tonearmDrag(camera: camera, size: proxy.size))
        }
        .background(.black)
        .ignoresSafeArea()
    }

    private func camera(for size: CGSize) -> TopDownCamera {
        TurntableScene.camera(for: size, trailingInset: trailingInset)
    }

    private func tonearmDrag(camera: TopDownCamera, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let scene else { return }
                // The arm is grabbed at roughly its own height above the plinth.
                let point = camera.tablePoint(for: value.location, in: size, planeHeight: 0.035)
                if dragStarted == nil {
                    let onArm = model.beginDrag(at: point, currentSwing: scene.currentSwing)
                    dragStarted = onArm
                    if !onArm {
                        model.press(at: camera.tablePoint(for: value.location, in: size, planeHeight: 0.008))
                    }
                }
                if dragStarted == true {
                    model.drag(to: point)
                }
            }
            .onEnded { value in
                if dragStarted == true {
                    model.endDrag()
                } else {
                    model.release(at: camera.tablePoint(for: value.location, in: size, planeHeight: 0.008))
                }
                dragStarted = nil
            }
    }
}
