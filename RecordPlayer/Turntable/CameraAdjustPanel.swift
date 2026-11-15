import SwiftUI

/// Keeps the camera poses the user has adjusted, per deck, between launches.
enum CameraPoseStore {
    private static func key(_ deck: String) -> String { "cameraPoses.\(deck)" }

    static func load(deck: String) -> [TurntableCameraView: CameraPose] {
        guard let data = UserDefaults.standard.data(forKey: key(deck)),
              let saved = try? JSONDecoder().decode([String: CameraPose].self, from: data)
        else { return [:] }
        var poses: [TurntableCameraView: CameraPose] = [:]
        for (name, pose) in saved {
            if let view = TurntableCameraView(rawValue: name) { poses[view] = pose }
        }
        return poses
    }

    static func save(_ poses: [TurntableCameraView: CameraPose], deck: String) {
        var named: [String: CameraPose] = [:]
        for (view, pose) in poses { named[view.rawValue] = pose }
        UserDefaults.standard.set(try? JSONEncoder().encode(named), forKey: key(deck))
    }
}

/// Sliders for the camera of the view being shown. Press A to show or hide it.
struct CameraAdjustPanel: View {
    let view: TurntableCameraView
    /// The deck's own pose for this view, which Reset goes back to.
    let original: CameraPose
    @Binding var pose: CameraPose
    let save: () -> Void
    let reset: () -> Void

    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("\(view.title) view")
                .font(.system(size: 13, weight: .semibold))
                .padding(.bottom, 2)

            row("Side", $pose.yaw, -180...180, unit: "°")
            row("Height", $pose.elevation, 5...90, unit: "°")
            row("Roll", $pose.roll, -180...180, unit: "°")
            row("Zoom", zoom, 3...40, unit: " cm")
            row("Shift ←→", $pose.offset.x, -0.2...0.2, scale: 100, unit: " cm")
            row("Shift ↑↓", $pose.offset.y, -0.1...0.1, scale: 100, unit: " cm")
            row("Shift near/far", $pose.offset.z, -0.2...0.2, scale: 100, unit: " cm")
            row("Blur", $pose.blur, 0...2.5, digits: 2)

            HStack {
                Button("Reset") { reset() }
                Spacer()
                Button(saved ? "Saved" : "Save") {
                    save()
                    saved = true
                }
                .keyboardShortcut("s", modifiers: .command)
            }
            .controlSize(.small)
            .padding(.top, 4)
        }
        .font(.system(size: 11))
        .padding(14)
        .frame(width: 250)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .environment(\.colorScheme, .dark)
        .onChange(of: pose) { saved = false }
        .onChange(of: view) { saved = false }
    }

    /// Half the picture height around the target, in centimetres. The width keeps the view's own shape.
    private var zoom: Binding<Float> {
        Binding(
            get: { pose.halfExtent.y * 100 },
            set: { size in
                let shape = original.halfExtent.x / max(original.halfExtent.y, 0.001)
                pose.halfExtent = [size / 100 * shape, size / 100]
            }
        )
    }

    private func row(
        _ title: String, _ value: Binding<Float>, _ range: ClosedRange<Float>,
        scale: Float = 1, unit: String = "", digits: Int = 1
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(title).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.\(digits)f", value.wrappedValue * scale) + unit).monospacedDigit()
            }
            Slider(value: value, in: range)
                .controlSize(.mini)
        }
    }
}
