import SwiftUI
import TurntableCore

/// Where the HUD sits. The playback panel fills the right edge from top to bottom and the deck is framed in the
/// space left of it. The camera views are a strip along the bottom, over the deck's space. H hides the panel, V the strip.
enum HUDLayout {
    /// Gap between a panel and the window's edges, and between the playback panel and the deck.
    static let inset: CGFloat = 16
    static let detailWidth: CGFloat = 300
    /// Padding inside the playback panel.
    static let detailPadding: CGFloat = 16
    /// Size of one view's thumbnail in the strip.
    static let thumbnail = CGSize(width: 128, height: 72)

    /// What the deck keeps clear at the right while the playback panel shows.
    static let rightRoom = inset + detailWidth + inset

    /// The smallest window that leaves the deck fully visible beside the panel.
    static let minimumSize = CGSize(width: 1100, height: 720)
}

extension Color {
    /// The one accent: the deck's strobe blue. For the playing indicator, the progress and the selected view.
    static let hudAccent = Color(red: 0.45, green: 0.65, blue: 1.0)
}

extension Font {
    /// Small uppercase metadata: tracked, monospaced.
    static let hudLabel = Font.system(size: 10, weight: .medium, design: .monospaced)
}

extension View {
    /// Dark translucent glass with a hairline border.
    func hudGlass(radius: CGFloat = 10) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.black.opacity(0.45)))
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        }
        .environment(\.colorScheme, .dark)
    }

    /// The look of a metadata label.
    func hudLabelStyle(_ opacity: Double = 0.5) -> some View {
        font(.hudLabel)
            .tracking(1.1)
            .textCase(.uppercase)
            .foregroundStyle(.white.opacity(opacity))
    }
}

/// A round button that brings a hidden panel back. It fades while the pointer rests.
struct HUDShowButton: View {
    let symbol: String
    let label: String
    let help: String
    let pointer: PointerActivity
    let show: () -> Void

    var body: some View {
        HUDButton(symbol: symbol, size: 11, label: label, help: help, action: show)
            .background(Circle().fill(.ultraThinMaterial).overlay(Circle().fill(.black.opacity(0.45))))
            .overlay(Circle().strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
            .clipShape(Circle())
            .environment(\.colorScheme, .dark)
            .opacity(pointer.isIdle ? 0 : 1)
            .animation(.easeOut(duration: pointer.isIdle ? 0.6 : 0.15), value: pointer.isIdle)
    }
}

/// Knows whether the pointer has rested over the window for a few seconds.
@MainActor
@Observable
final class PointerActivity {
    private(set) var isIdle = false
    @ObservationIgnored private var lastMove = ContinuousClock.now
    @ObservationIgnored private var watch: Task<Void, Never>?

    private let restAfter: Duration = .seconds(2.5)

    func moved() {
        lastMove = .now
        if isIdle { isIdle = false }
        guard watch == nil else { return }
        watch = Task { [weak self] in
            while let self {
                let due = lastMove + restAfter
                if ContinuousClock.now >= due {
                    isIdle = true
                    watch = nil
                    return
                }
                try? await Task.sleep(until: due)
            }
        }
    }
}

/// An SF Symbol button with the panel's hover and pressed states.
struct HUDButton: View {
    let symbol: String
    let size: CGFloat
    let label: String
    let help: String
    var side: CGFloat = 30
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: side, height: side)
        }
        .buttonStyle(HUDButtonStyle())
        .help(help)
        .accessibilityLabel(label)
    }
}

struct HUDButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HUDButtonBody(configuration: configuration)
    }
}

private struct HUDButtonBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        configuration.label
            .foregroundStyle(.white.opacity(foreground))
            .background(shape.fill(.white.opacity(fill)))
            .contentShape(shape)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }

    private var foreground: Double {
        guard isEnabled else { return 0.2 }
        return isHovered || configuration.isPressed ? 0.94 : 0.62
    }

    private var fill: Double {
        guard isEnabled else { return 0 }
        if configuration.isPressed { return 0.2 }
        return isHovered ? 0.08 : 0
    }
}

/// The turntable with `room` (0...1) of the playback panel's space kept clear at the right. Animating `room`
/// glides the deck left as the panel comes and back as it goes.
struct HUDFramedTurntable: View, Animatable {
    let model: TurntableModel
    let cameraView: TurntableCameraView
    let adjustedPoses: [TurntableCameraView: CameraPose]
    var room: Double

    nonisolated var animatableData: Double {
        get { room }
        set { room = newValue }
    }

    var body: some View {
        GeometryReader { proxy in
            // The scene takes its first poses from the first view it is made with, so it waits for a real size.
            if proxy.size.width > HUDLayout.rightRoom, proxy.size.height > 0 {
                TurntableView(model: model, cameraView: cameraView, adjustedPoses: poses(in: proxy.size))
            }
        }
        .ignoresSafeArea()
    }

    private func poses(in size: CGSize) -> [TurntableCameraView: CameraPose] {
        guard room > 0 else { return adjustedPoses }
        var poses: [TurntableCameraView: CameraPose] = [:]
        for view in TurntableCameraView.allCases {
            let pose = adjustedPoses[view] ?? model.spec.pose(for: view)
            poses[view] = pose.leavingRoom(left: 0, right: HUDLayout.rightRoom * room, in: size)
        }
        return poses
    }
}

extension CameraPose {
    /// The same picture with `left` and `right` points kept clear at the sides of a view of `size`; see
    /// `CameraFraming.leavingRoom`.
    func leavingRoom(left: CGFloat, right: CGFloat, in size: CGSize) -> CameraPose {
        let framing = framing
        let room = framing.leavingRoom(left: left, right: right, in: size)
        var pose = self
        pose.halfExtent = room.halfExtent
        pose.offset += room.target - framing.target
        return pose
    }
}
