import AVFoundation

/// Plays a folder of audio files as one record. Used until Apple Music is wired in, and for testing without it.
@MainActor
final class LocalPlayback: NSObject, RecordPlayback {
    private(set) var record: Record?
    private(set) var trackIndex = 0
    var onRecordEnded: (() -> Void)?

    private let urls: [URL]
    private var player: AVAudioPlayer?
    private var pausedTime: Double = 0
    /// Silences the output, for automated checks.
    var isMuted = false

    /// The test record bundled with debug builds, or the folder given with `--record <folder>`.
    static func testRecord() -> LocalPlayback? {
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--record"), arguments.count > flag + 1 {
            return LocalPlayback(folder: URL(fileURLWithPath: arguments[flag + 1]), title: "Test record")
        }
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("TestRecord") else { return nil }
        return LocalPlayback(folder: folder, title: "Test record")
    }

    /// Nil when the folder holds no playable audio.
    init?(folder: URL, title: String) {
        let extensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aiff", "flac"]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var urls: [URL] = []
        var tracks: [RecordTrack] = []
        for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where extensions.contains(url.pathExtension.lowercased()) {
            guard let probe = try? AVAudioPlayer(contentsOf: url), probe.duration > 0 else { continue }
            let name = Self.name(from: url)
            urls.append(url)
            tracks.append(RecordTrack(title: name.title, artist: name.artist, duration: probe.duration))
        }
        guard !tracks.isEmpty else { return nil }
        self.urls = urls
        let artists = Set(tracks.map(\.artist))
        self.record = Record(
            title: title,
            artist: artists.count == 1 ? tracks[0].artist : "Various artists",
            tracks: tracks
        )
        super.init()
    }

    /// "artist-some-title-123456.mp3" becomes ("Some title", "artist").
    static func name(from url: URL) -> (title: String, artist: String) {
        var parts = url.deletingPathExtension().lastPathComponent.split(separator: "-").map(String.init)
        if parts.count > 1, let last = parts.last, last.allSatisfy(\.isNumber) { parts.removeLast() }
        guard parts.count > 1 else { return (parts.first ?? "Untitled", "Unknown artist") }
        let artist = parts.removeFirst().replacingOccurrences(of: "_", with: " ")
        let title = parts.joined(separator: " ")
        return (title.prefix(1).uppercased() + title.dropFirst(), artist)
    }

    var time: Double { player?.currentTime ?? pausedTime }
    var isPlaying: Bool { player?.isPlaying ?? false }

    func play(track: Int, at time: Double) {
        guard urls.indices.contains(track) else { return }
        player?.stop()
        guard let next = try? AVAudioPlayer(contentsOf: urls[track]) else { return }
        trackIndex = track
        next.delegate = self
        next.volume = isMuted ? 0 : 1
        next.currentTime = min(max(0, time), max(0, next.duration - 0.05))
        next.play()
        player = next
    }

    func pause() {
        guard let player else { return }
        pausedTime = player.currentTime
        player.stop()
        self.player = nil
    }
}

extension LocalPlayback: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ finished: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(finished)
        let duration = finished.duration
        Task { @MainActor in
            guard let player, ObjectIdentifier(player) == id else { return }
            if trackIndex + 1 < urls.count {
                play(track: trackIndex + 1, at: 0)
            } else {
                pausedTime = duration
                self.player = nil
                onRecordEnded?()
            }
        }
    }
}
