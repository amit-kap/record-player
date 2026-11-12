import SwiftUI

struct ContentView: View {
    @State private var turntable = TurntableModel()

    var body: some View {
        TurntableView(model: turntable)
            .frame(minWidth: 800, minHeight: 500)
            .background { keyboardShortcuts }
        #if DEBUG
            .task {
                if await TurntableSnapshot.runIfRequested() {
                    exit(0)
                }
            }
        #endif
    }

    /// The buttons live on the turntable itself; these give them keys and VoiceOver names.
    private var keyboardShortcuts: some View {
        Group {
            Button("Play or stop") { turntable.togglePlay() }
                .keyboardShortcut(.space, modifiers: [])
            Button("Previous track") { turntable.previousTrack() }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("Next track") { turntable.nextTrack() }
                .keyboardShortcut(.rightArrow, modifiers: [])
        }
        .opacity(0)
    }
}
