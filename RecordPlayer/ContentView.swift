import SwiftUI

struct ContentView: View {
    @State private var turntable = TurntableModel(playback: ContentView.playback())
    @State private var mediaKeys = MediaKeys()
    @State private var cameraView: TurntableCameraView = .top
    @State private var adjustedPoses: [TurntableCameraView: CameraPose] = [:]
    @State private var isAdjustingCamera = false

    var body: some View {
        TurntableView(model: turntable, cameraView: cameraView, adjustedPoses: adjustedPoses)
            .frame(minWidth: 800, minHeight: 500)
            .overlay(alignment: .topTrailing) {
                if isAdjustingCamera {
                    CameraAdjustPanel(
                        view: cameraView,
                        original: turntable.spec.pose(for: cameraView),
                        pose: Binding(
                            get: { adjustedPoses[cameraView] ?? turntable.spec.pose(for: cameraView) },
                            set: { adjustedPoses[cameraView] = $0 }
                        ),
                        save: { CameraPoseStore.save(adjustedPoses, deck: turntable.spec.id) },
                        reset: {
                            adjustedPoses[cameraView] = nil
                            CameraPoseStore.save(adjustedPoses, deck: turntable.spec.id)
                        }
                    )
                    .padding(.top, 36)
                    .padding(.trailing, 16)
                    .transition(.opacity)
                }
            }
            .onAppear { adjustedPoses = CameraPoseStore.load(deck: turntable.spec.id) }
            .background { keyboardShortcuts }
            .onAppear { mediaKeys.connect(to: turntable) }
            .onChange(of: turntable.nowPlaying) { mediaKeys.update(from: turntable) }
            .onChange(of: turntable.isMotorOn) { mediaKeys.update(from: turntable) }
        #if DEBUG
            .task {
                if CommandLine.arguments.contains("--adjust") { isAdjustingCamera = true }
                // `--autoplay` presses start after launch, for checking the playing state on screen.
                if CommandLine.arguments.contains("--autoplay") {
                    try? await Task.sleep(for: .seconds(1.5))
                    turntable.togglePlay()
                    try? await Task.sleep(for: .seconds(2.5))
                    turntable.nextTrack()
                    // `--view side` then glides to that view, for checking a change of view on screen.
                    if let flag = CommandLine.arguments.firstIndex(of: "--view"),
                       CommandLine.arguments.count > flag + 1,
                       let view = TurntableCameraView(rawValue: CommandLine.arguments[flag + 1]) {
                        cameraView = view
                    }
                }
            }
        #endif
    }

    /// Until Apple Music is wired in, debug builds play the bundled test record.
    private static func playback() -> RecordPlayback? {
        #if DEBUG
        if CommandLine.arguments.contains("--snapshot") { return nil }
        let playback = LocalPlayback.testRecord()
        playback?.isMuted = CommandLine.arguments.contains("--mute")
        return playback
        #else
        return nil
        #endif
    }

    /// The buttons live on the turntable itself; these give them keys and VoiceOver names.
    private var keyboardShortcuts: some View {
        Group {
            Button("Play or pause") { turntable.togglePlay() }
                .keyboardShortcut(.space, modifiers: [])
            Button("Previous track") { turntable.previousTrack() }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("Next track") { turntable.nextTrack() }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("Adjust camera") { withAnimation(.easeOut(duration: 0.15)) { isAdjustingCamera.toggle() } }
                .keyboardShortcut("a", modifiers: [])
            ForEach(Array(TurntableCameraView.allCases.enumerated()), id: \.element) { index, view in
                Button("\(view.title) view") { cameraView = view }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
            }
        }
        .opacity(0)
    }
}
