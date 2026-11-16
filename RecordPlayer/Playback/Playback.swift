import CoreGraphics
import Foundation

/// A cover image that loads when asked. Local files and Apple Music both fit: the image comes from `load`,
/// which may fetch it over the network. Two artworks are equal when their ids are.
struct Artwork: Sendable, Equatable {
    /// Stable for the same picture, so the cache can recognise it.
    let id: String
    private let load: @Sendable (_ pixels: Int) async -> CGImage?

    /// `load` returns the cover as a square of about `pixels` on a side, or nil when it cannot.
    init(id: String, load: @escaping @Sendable (_ pixels: Int) async -> CGImage?) {
        self.id = id
        self.load = load
    }

    /// The cover at about `pixels` on a side. Each id and size is loaded once.
    func image(pixels: Int) async -> CGImage? {
        await ArtworkCache.shared.image(for: self, pixels: pixels)
    }

    static func == (lhs: Artwork, rhs: Artwork) -> Bool { lhs.id == rhs.id }

    fileprivate func loadUncached(pixels: Int) async -> CGImage? { await load(pixels) }
}

/// Keeps decoded covers, so changing tracks back and forth does not decode them again.
private actor ArtworkCache {
    static let shared = ArtworkCache()

    private struct Key: Hashable {
        let id: String
        let pixels: Int
    }

    private var images: [Key: CGImage] = [:]
    private var loading: [Key: Task<CGImage?, Never>] = [:]

    func image(for artwork: Artwork, pixels: Int) async -> CGImage? {
        let key = Key(id: artwork.id, pixels: pixels)
        if let cached = images[key] { return cached }
        if let running = loading[key] { return await running.value }
        let task = Task { await artwork.loadUncached(pixels: pixels) }
        loading[key] = task
        let image = await task.value
        loading[key] = nil
        if let image { images[key] = image }
        return image
    }
}

struct RecordTrack: Sendable, Equatable {
    var title: String
    var artist: String
    var album: String
    /// Nil when the track has no cover of its own; the record's is used then.
    var artwork: Artwork?
    /// Seconds.
    var duration: Double
}

/// What sits on the platter: an album or a playlist.
struct Record: Sendable, Equatable, Identifiable {
    /// Stable for the same album or playlist, so the last loaded record can be found again.
    var id: String
    var title: String
    var artist: String
    var artwork: Artwork?
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
    /// Stops the sound and makes `record` the current one, from its first track. Nil empties the player.
    func load(_ record: Record?)
}
