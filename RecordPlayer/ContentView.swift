import SwiftUI

struct ContentView: View {
    @State private var turntable = Launch.setup.model
    /// The records that can be loaded.
    private let records = Launch.setup.records
    @State private var mediaKeys = MediaKeys()
    @State private var cameraView: TurntableCameraView = .top
    @State private var adjustedPoses: [TurntableCameraView: CameraPose] = [:]
    @State private var isAdjustingCamera = false
    /// Whether the playback panel and the views strip show, each on its own: the saved choice, or a launch flag's
    /// for that launch only. Plain state rather than `@AppStorage`, so a toggle's animation reaches the transition.
    @State private var isPlaybackShown = ContentView.hudFlag
        ?? UserDefaults.standard.object(forKey: ContentView.playbackKey) as? Bool ?? true
    @State private var isViewsShown = ContentView.hudFlag
        ?? UserDefaults.standard.object(forKey: ContentView.viewsKey) as? Bool ?? true
    @State private var pointer = PointerActivity()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HUDFramedTurntable(
            model: turntable, cameraView: cameraView, adjustedPoses: adjustedPoses, room: isPlaybackShown ? 1 : 0
        )
            // With reduced motion the deck moves at once, while the panels only fade.
            .animation(reduceMotion ? nil : Self.hudMotion, value: isPlaybackShown)
            .frame(minWidth: HUDLayout.minimumSize.width, minHeight: HUDLayout.minimumSize.height)
            .overlay(alignment: .trailing) {
                if isPlaybackShown {
                    HUDDetailPanel(model: turntable, records: records, choose: load, hide: togglePlayback)
                        .padding(HUDLayout.inset)
                        // Up into the title bar's space: the panel runs the window's full height.
                        .ignoresSafeArea()
                        .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottom) {
                // Centred under the deck, in the space the playback panel leaves.
                Group {
                    if isViewsShown {
                        HUDViewStrip(cameraView: $cameraView, hide: toggleViews)
                            .padding(.bottom, HUDLayout.inset)
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    } else {
                        HUDShowButton(
                            symbol: "rectangle.split.3x1", label: "Show views", help: "Show views (V)",
                            pointer: pointer, show: toggleViews
                        )
                        .padding(.bottom, HUDLayout.inset)
                        .transition(.opacity)
                    }
                }
                .padding(.trailing, isPlaybackShown ? HUDLayout.rightRoom : 0)
            }
            .overlay(alignment: .topTrailing) {
                if !isPlaybackShown {
                    // Where the panel's own hide button sits, so the toggle stays in one place.
                    HUDShowButton(
                        symbol: "sidebar.right", label: "Show playback", help: "Show playback (H)",
                        pointer: pointer, show: togglePlayback
                    )
                        .padding(.top, 29)
                        .padding(.trailing, 25)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
            }
            .onContinuousHover { _ in pointer.moved() }
            .onAppear { pointer.moved() }
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
                    .padding(.trailing, isPlaybackShown ? HUDLayout.rightRoom : 16)
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

    /// Loading a record by hand is the user's choice, so it is saved.
    private func load(_ record: Record?) {
        turntable.load(record)
        LastRecord.save(record)
    }

    /// The panels and the deck move with this one curve, so they arrive together.
    private static let hudMotion = Animation.easeOut(duration: 0.3)

    private static let playbackKey = "hudShown"
    private static let viewsKey = "viewsShown"

    /// `--hud` and `--no-hud` show or hide the panel and the strip for one launch, for checking both on screen.
    private static var hudFlag: Bool? {
        #if DEBUG
        if CommandLine.arguments.contains("--no-hud") { return false }
        if CommandLine.arguments.contains("--hud") { return true }
        #endif
        return nil
    }

    /// A toggle is the user's choice, so it is saved.
    private func togglePlayback() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : Self.hudMotion) { isPlaybackShown.toggle() }
        UserDefaults.standard.set(isPlaybackShown, forKey: Self.playbackKey)
        // The button that brings it back shows for a moment, even when the pointer is elsewhere.
        pointer.moved()
    }

    private func toggleViews() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : Self.hudMotion) { isViewsShown.toggle() }
        UserDefaults.standard.set(isViewsShown, forKey: Self.viewsKey)
        pointer.moved()
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
            Button("Show or hide playback") { togglePlayback() }
                .keyboardShortcut("h", modifiers: [])
            Button("Show or hide views") { toggleViews() }
                .keyboardShortcut("v", modifiers: [])
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

/// What the app starts with. Until Apple Music is wired in, debug builds play the bundled test records.
@MainActor
private enum Launch {
    static let setup: (model: TurntableModel, records: [Record]) = {
        #if DEBUG
        // A snapshot renders its own scene; the app never plays for it.
        guard !CommandLine.arguments.contains("--snapshot"), let library = LocalPlayback.testLibrary() else {
            return (TurntableModel(), [])
        }
        library.playback.isMuted = CommandLine.arguments.contains("--mute")
        let first = LastRecord.initial(from: library.records, preferred: library.preferred)
        library.playback.load(first)
        return (TurntableModel(playback: library.playback, record: first), library.records)
        #else
        return (TurntableModel(), [])
        #endif
    }()
}
