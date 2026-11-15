import SwiftUI
import TurntableCore

/// The floating panel under the deck: the song under the needle, its controls and the camera views.
/// Press H or its chevron to hide it.
struct HUDPanel: View {
    let model: TurntableModel
    @Binding var cameraView: TurntableCameraView
    let hide: () -> Void

    /// Height of the panel itself.
    static let height: CGFloat = 52
    /// Gap between the panel and the window's edges.
    static let inset: CGFloat = 14
    /// The band at the bottom of the window that the deck keeps clear while the panel shows.
    static let band: CGFloat = height + inset

    var body: some View {
        HStack(spacing: 12) {
            HUDSongInfo(model: model)
            divider
            transport
            divider
            viewSwitcher
            HUDButton(symbol: "chevron.down", size: 11, label: "Hide controls", help: "Hide controls (H)", action: hide)
        }
        .padding(.leading, 9)
        .padding(.trailing, 8)
        .frame(maxWidth: 760, minHeight: Self.height, maxHeight: Self.height)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black.opacity(0.45)))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Player controls")
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.1))
            .frame(width: 1, height: 22)
            .accessibilityHidden(true)
    }

    /// The same actions as space and the arrow keys.
    private var transport: some View {
        let isLoaded = model.record != nil && !model.isDragging
        let isOnRecord = isLoaded && model.isNeedleDown
        return HStack(spacing: 2) {
            HUDButton(symbol: "backward.fill", size: 12, label: "Previous track", help: "Previous track (←)") {
                model.previousTrack()
            }
            .disabled(!isOnRecord)
            HUDButton(
                symbol: model.isPlaying ? "pause.fill" : "play.fill", size: 15,
                label: model.isPlaying ? "Pause" : "Play", help: "Play or pause (space)"
            ) {
                model.togglePlay()
            }
            .disabled(!isLoaded)
            HUDButton(symbol: "forward.fill", size: 12, label: "Next track", help: "Next track (→)") {
                model.nextTrack()
            }
            .disabled(!isOnRecord || model.currentTrack + 1 >= model.layout.trackCount)
        }
    }

    private var viewSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(Array(TurntableCameraView.allCases.enumerated()), id: \.element) { index, view in
                Button {
                    cameraView = view
                } label: {
                    Text(view.title)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 9)
                        .frame(minWidth: 28, minHeight: 28)
                }
                .buttonStyle(HUDButtonStyle(isSelected: view == cameraView))
                .help("\(view.title) view (\(index + 1))")
                .accessibilityLabel("\(view.title) view")
                .accessibilityAddTraits(view == cameraView ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.05)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Camera view")
    }
}

/// Cover, title, artist, album and time, read by VoiceOver as one line.
private struct HUDSongInfo: View {
    let model: TurntableModel

    var body: some View {
        HStack(spacing: 10) {
            HUDCover(artwork: artwork)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(model.record == nil ? 0.5 : 0.88))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            time
        }
        .animation(.easeOut(duration: 0.2), value: model.nowPlaying)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary)
    }

    private var artwork: Artwork? {
        model.nowPlaying == nil ? model.record?.artwork ?? model.nowPlayingArtwork : model.nowPlayingArtwork
    }

    private var title: String {
        model.nowPlaying?.title ?? model.record?.title ?? "No record on the platter"
    }

    private var subtitle: String? {
        if let track = model.nowPlaying { return "\(track.artist) · \(track.album)" }
        guard let record = model.record else { return nil }
        let count = record.tracks.count
        return "\(record.artist) · \(count) \(count == 1 ? "track" : "tracks")"
    }

    /// Elapsed and length while a track plays; the record's length at rest. The widest possible text holds the
    /// space, so nothing shifts as the seconds tick.
    @ViewBuilder private var time: some View {
        if let track = model.nowPlaying {
            ZStack(alignment: .trailing) {
                Text("00:00 / 00:00").hidden()
                Text(Self.clock(model.elapsedSeconds))
                    .foregroundStyle(.white.opacity(0.72))
                    + Text(" / " + Self.clock(Int(track.duration.rounded())))
                    .foregroundStyle(.white.opacity(0.36))
            }
            .font(.system(size: 12, weight: .medium).monospacedDigit())
        } else if let record = model.record {
            Text(Self.clock(Int(record.tracks.map(\.duration).reduce(0, +).rounded())))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.36))
        }
    }

    private var spokenSummary: String {
        if let track = model.nowPlaying {
            let state = model.isPlaying ? "Playing" : "Paused"
            return "\(state): \(track.title), by \(track.artist), from \(track.album). "
                + "\(Self.clock(model.elapsedSeconds)) of \(Self.clock(Int(track.duration.rounded())))"
        }
        guard let record = model.record else { return "No record on the platter" }
        return "On the platter: \(record.title), by \(record.artist). Not playing"
    }

    /// 75 seconds becomes "1:15".
    static func clock(_ seconds: Int) -> String {
        "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}

/// The cover as a small square, loaded at the screen's pixel size. It keeps the last cover until the next one is
/// ready, so a track change does not flash empty.
private struct HUDCover: View {
    let artwork: Artwork?

    private static let side: CGFloat = 34

    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(.white.opacity(0.06))
            .overlay {
                if let image {
                    Image(decorative: image, scale: displayScale)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                } else {
                    Image(systemName: "opticaldisc")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .frame(width: Self.side, height: Self.side)
            .animation(.easeOut(duration: 0.2), value: image.map(ObjectIdentifier.init))
            .task(id: "\(artwork?.id ?? "")@\(pixels)") {
                let loaded = await artwork?.image(pixels: pixels)
                if !Task.isCancelled { image = loaded }
            }
    }

    private var pixels: Int { Int((Self.side * displayScale).rounded(.up)) }
}

/// A round button that brings the hidden panel back. It fades while the pointer rests.
struct HUDShowButton: View {
    let pointer: PointerActivity
    let show: () -> Void

    var body: some View {
        HUDButton(symbol: "chevron.up", size: 11, label: "Show controls", help: "Show controls (H)", action: show)
            .background(Circle().fill(.ultraThinMaterial).overlay(Circle().fill(.black.opacity(0.45))))
            .overlay(Circle().strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
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
private struct HUDButton: View {
    let symbol: String
    let size: CGFloat
    let label: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(HUDButtonStyle())
        .help(help)
        .accessibilityLabel(label)
    }
}

private struct HUDButtonStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        HUDButtonBody(configuration: configuration, isSelected: isSelected)
    }
}

private struct HUDButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool

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
        return isSelected || isHovered || configuration.isPressed ? 0.94 : 0.62
    }

    private var fill: Double {
        guard isEnabled else { return 0 }
        if configuration.isPressed { return 0.2 }
        if isSelected { return 0.14 }
        return isHovered ? 0.08 : 0
    }
}

/// The turntable with `room` (0...1) of the panel's band kept clear at the bottom. Animating `room` glides the
/// deck up as the panel comes and back down as it goes.
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
            if proxy.size.height > HUDPanel.band {
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
            poses[view] = pose.leavingRoom(HUDPanel.band * room, in: size)
        }
        return poses
    }
}

extension CameraPose {
    /// The same picture with `band` points kept clear at the bottom of a view of `size`; see
    /// `CameraFraming.leavingRoom`.
    func leavingRoom(_ band: CGFloat, in size: CGSize) -> CameraPose {
        let framing = framing
        let room = framing.leavingRoom(band, in: size)
        var pose = self
        pose.halfExtent = room.halfExtent
        pose.offset += room.target - framing.target
        return pose
    }
}
