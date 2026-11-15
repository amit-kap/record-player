import SwiftUI

@main
struct RecordPlayerApp: App {
    init() {
        #if DEBUG
        // Command-line renders and checks run without waiting for a window.
        Task { @MainActor in
            if await TurntableSnapshot.runIfRequested() { exit(0) }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentMinSize)
    }
}
