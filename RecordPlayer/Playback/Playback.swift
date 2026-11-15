import Foundation

struct RecordTrack: Sendable, Equatable {
    var title: String
    var artist: String
    /// Seconds.
    var duration: Double
}

/// What sits on the platter: an album or a playlist.
struct Record: Sendable, Equatable {
    var title: String
    var artist: String
    var tracks: [RecordTrack]
}

/// Plays the tracks of one record. The turntable decides when and from where; this only makes the sound.
/// Local files implement it now; Apple Music implements it in M1.
@MainActor
protocol RecordPlayback: AnyObject {
    var record: Record? { get }
    /// The track being played, counted from 0.
    var trackIndex: Int { get }
    /// Seconds into the current track.
    var time: Double { get }
    var isPlaying: Bool { get }
    /// Called once when the last track has played to its end.
    var onRecordEnded: (() -> Void)? { get set }

    /// Plays from `time` seconds into `track`, and carries on through the following tracks.
    func play(track: Int, at time: Double)
    /// Stops the sound and keeps the position.
    func pause()
}
