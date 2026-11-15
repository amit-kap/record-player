import AVFoundation
import AudioToolbox
import CoreText
import ImageIO
import TurntableCore

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
            let tags = Self.tags(of: url)
            urls.append(url)
            tracks.append(RecordTrack(
                title: name.title, artist: name.artist, album: tags.album ?? title,
                artwork: Self.artwork(for: url, title: name.title, embedded: tags.cover),
                duration: probe.duration
            ))
        }
        guard !tracks.isEmpty else { return nil }
        self.urls = urls
        let artists = Set(tracks.map(\.artist))
        self.record = Record(
            title: title,
            artist: artists.count == 1 ? tracks[0].artist : "Various artists",
            artwork: nil,
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

    /// The album name and embedded cover of an audio file, when it has them.
    private static func tags(of url: URL) -> (album: String?, cover: Data?) {
        var file: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &file) == noErr, let file else { return (nil, nil) }
        defer { AudioFileClose(file) }

        var info: Unmanaged<CFDictionary>?
        var size = UInt32(MemoryLayout<Unmanaged<CFDictionary>?>.size)
        var album: String?
        if AudioFileGetProperty(file, kAudioFilePropertyInfoDictionary, &size, &info) == noErr,
           let dictionary = info?.takeRetainedValue() as? [String: Any],
           let name = (dictionary[kAFInfoDictionary_Album as String] as? String)?.trimmingCharacters(in: .whitespaces),
           !name.isEmpty {
            album = name
        }

        var art: Unmanaged<CFData>?
        size = UInt32(MemoryLayout<Unmanaged<CFData>?>.size)
        var cover: Data?
        if AudioFileGetProperty(file, kAudioFilePropertyAlbumArtwork, &size, &art) == noErr, let art {
            cover = art.takeRetainedValue() as Data
        }
        return (album, cover)
    }

    /// The embedded cover when the file has one that decodes; otherwise a generated one with the title on it.
    private static func artwork(for url: URL, title: String, embedded: Data?) -> Artwork {
        let id = "local:" + url.lastPathComponent
        if let embedded, decode(embedded, pixels: 16) != nil {
            return Artwork(id: id) { pixels in decode(embedded, pixels: pixels) }
        }
        return Artwork(id: id) { pixels in generatedCover(title: title, pixels: pixels) }
    }

    /// Decodes image data to at most `pixels` on its longer side.
    private nonisolated static func decode(_ data: Data, pixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels,
        ] as CFDictionary)
    }

    /// A square cover in a colour taken from the title, with the title centred above the middle, inside the circle
    /// a round label crops it to.
    private nonisolated static func generatedCover(title: String, pixels: Int) -> CGImage? {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let hue = CoverColor.hue(for: title)
        let top = CGColor(colorSpace: space, components: hsb(hue, 0.55, 0.85) + [1])!
        let bottom = CGColor(colorSpace: space, components: hsb(hue, 0.75, 0.35) + [1])!
        let side = CGFloat(pixels)
        if let gradient = CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(
                gradient, start: CGPoint(x: 0, y: side), end: CGPoint(x: 0, y: 0), options: []
            )
        }
        let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, side * 0.08, nil)
        var alignment = CTTextAlignment.center
        let centred = withUnsafeBytes(of: &alignment) { bytes in
            CTParagraphStyleCreate([CTParagraphStyleSetting(
                spec: .alignment, valueSize: bytes.count, value: bytes.baseAddress!
            )], 1)
        }
        let text = NSAttributedString(string: title, attributes: [
            .font: font,
            .foregroundColor: CGColor(gray: 1, alpha: 0.95),
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): centred,
        ])
        // Origin bottom-left: a band in the upper half whose corners stay inside the circle.
        let area = CGRect(x: side * 0.2, y: side * 0.54, width: side * 0.6, height: side * 0.32)
        let frame = CTFramesetterCreateFrame(
            CTFramesetterCreateWithAttributedString(text), CFRangeMake(0, 0), CGPath(rect: area, transform: nil), nil
        )
        CTFrameDraw(frame, context)
        return context.makeImage()
    }

    /// Hue, saturation and brightness (each 0...1) as red, green and blue.
    private nonisolated static func hsb(_ hue: Double, _ saturation: Double, _ brightness: Double) -> [CGFloat] {
        let sector = hue * 6
        let fraction = sector - sector.rounded(.down)
        let low = brightness * (1 - saturation)
        let falling = brightness * (1 - saturation * fraction)
        let rising = brightness * (1 - saturation * (1 - fraction))
        let rgb: (Double, Double, Double) = switch Int(sector) % 6 {
        case 0: (brightness, rising, low)
        case 1: (falling, brightness, low)
        case 2: (low, brightness, rising)
        case 3: (low, falling, brightness)
        case 4: (rising, low, brightness)
        default: (brightness, low, falling)
        }
        return [CGFloat(rgb.0), CGFloat(rgb.1), CGFloat(rgb.2)]
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
