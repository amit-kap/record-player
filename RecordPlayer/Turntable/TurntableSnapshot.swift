#if DEBUG
import CoreGraphics
import Foundation
import ImageIO
import Metal
import RealityKit
import TurntableCore
import UniformTypeIdentifiers

/// Debug only: renders the turntable to a PNG without a window, so the look can be checked from the command line.
///
///     RecordPlayer --snapshot out.png [--size 1280x800] [--view top|side|tonearm] [--play] [--track 2] [--swing 0.4]
///         [--frames 300] [--change lifting|dropping --progress 0.5] [--empty]
///
/// `--play` and `--track` play the test record muted, so the label carries the track's cover; without them the
/// record is silent and shows the placeholder label. `--change` swaps the record and stops in the middle of the
/// lift or the drop; `--empty` takes the record off.
extension Record {
    /// A silent record for stills without music: five tracks, so the needle has bands to drop on.
    static let placeholder = Record(
        id: "placeholder", title: "Placeholder", artist: "", artwork: nil,
        tracks: [190, 180, 210, 220, 200].enumerated().map {
            RecordTrack(title: "Track \($0.offset + 1)", artist: "", album: "", artwork: nil, duration: $0.element)
        }
    )
}

@MainActor
enum TurntableSnapshot {
    /// Renders and returns true when the launch arguments ask for a snapshot.
    static func runIfRequested() async -> Bool {
        let arguments = CommandLine.arguments
        if arguments.contains("--playback-check") {
            await playbackCheck()
            return true
        }
        guard let flag = arguments.firstIndex(of: "--snapshot"), arguments.count > flag + 1 else {
            return false
        }
        var width = 1280
        var height = 800
        if let value = value(after: "--size", in: arguments) {
            let parts = value.split(separator: "x").compactMap { Int($0) }
            if parts.count == 2 { (width, height) = (parts[0], parts[1]) }
        }
        let track = value(after: "--track", in: arguments).flatMap(Int.init)
        let phase: RecordChange.Phase? = switch value(after: "--change", in: arguments) {
        case "lifting": .lifting
        case "dropping": .dropping
        default: nil
        }
        do {
            try await render(
                to: URL(fileURLWithPath: arguments[flag + 1]),
                width: width,
                height: height,
                view: value(after: "--view", in: arguments).flatMap(TurntableCameraView.init(rawValue:)) ?? .top,
                play: arguments.contains("--play") || track != nil,
                track: track ?? 1,
                swing: value(after: "--swing", in: arguments).flatMap(Float.init),
                stopAt: phase.map { ($0, value(after: "--progress", in: arguments).flatMap(Float.init) ?? 0.5) },
                empty: arguments.contains("--empty")
            )
        } catch {
            FileHandle.standardError.write(Data("snapshot failed: \(error)\n".utf8))
        }
        return true
    }

    /// Plays the test record muted and prints what the turntable does, step by step. Exits with 1 when a check fails.
    private static func playbackCheck() async {
        guard let library = LocalPlayback.testLibrary() else {
            print("no test record")
            exit(1)
        }
        let playback = library.playback
        playback.isMuted = true
        playback.load(library.records[0])
        let model = TurntableModel(playback: playback)
        guard let scene = try? await TurntableScene(
            spec: model.spec, theme: .dark, trackStarts: model.trackStarts
        ) else {
            print("no scene")
            exit(1)
        }
        func run(_ seconds: Double, _ label: String) async {
            for _ in 0..<Int(seconds * 60) {
                scene.update(deltaTime: 1.0 / 60, model: model)
                try? await Task.sleep(for: .milliseconds(16))
            }
            let progress = model.geometry.progress(swing: scene.currentSwing)
            let expected = model.layout.progress(track: playback.trackIndex, time: playback.time)
            print(String(
                format: "%@: track %d, %d s, sounding %d, motor %d, needle %d, arm %.4f, music %.4f, title %@",
                label, model.currentTrack, model.elapsedSeconds, playback.isPlaying ? 1 : 0,
                model.isMotorOn ? 1 : 0, model.isNeedleDown ? 1 : 0, progress, expected,
                model.nowPlaying?.title ?? "-"
            ))
        }
        print("tracks:", model.record?.tracks.map { "\($0.title) / \($0.artist) / \(Int($0.duration)) s" } ?? [])
        print("starts:", model.trackStarts)
        print("albums:", model.record?.tracks.map(\.album) ?? [])
        var failures: [String] = []
        func check(_ condition: Bool, _ what: String) {
            print("check:", what, condition ? "ok" : "FAILED")
            if !condition { failures.append(what) }
        }
        /// Runs frames until the label shows `model`'s artwork in full, and checks that took under `limit` seconds.
        func labelSwap(to model: TurntableModel, _ what: String, within limit: Double = 1) async {
            let wanted = model.nowPlayingArtwork?.id
            let clock = ContinuousClock()
            let start = clock.now
            while scene.shownArtworkID != wanted, clock.now - start < .seconds(2) {
                scene.update(deltaTime: 1.0 / 60, model: model)
                try? await Task.sleep(for: .milliseconds(16))
            }
            let elapsed = clock.now - start
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
            print(String(format: "label: %@ in %.3f s", what, seconds))
            check(scene.shownArtworkID == wanted && seconds < limit, "label \(what) within \(limit) s")
        }
        check(model.nowPlayingArtwork != nil, "the record has artwork before playing")
        // The scene has seen nothing yet: the worst case, the cover is loaded only once it is needed.
        await labelSwap(to: model, "cold cover, no prewarm")
        // As in the app, the record sits on the platter for a moment before play is pressed.
        await run(1.5, "at rest")
        model.togglePlay()
        await labelSwap(to: model, "shows the first cover when play is pressed")
        await run(4, "start pressed")
        let first = model.nowPlayingArtwork?.id
        check(first != nil, "artwork while playing track 1")
        model.nextTrack()
        await labelSwap(to: model, "shows track 2's prewarmed cover after next", within: 0.5)
        await run(3, "next")
        let second = model.nowPlayingArtwork?.id
        check(second != nil && second != first, "artwork differs on track 2")
        if let artwork = model.nowPlayingArtwork {
            let image = await artwork.image(pixels: 256)
            check(image?.width == 256, "artwork loads at 256 px")
        }
        model.nextTrack()
        await labelSwap(to: model, "shows track 3's prewarmed cover after next", within: 0.5)
        await run(3, "next")
        model.nextTrack()
        await run(1, "next on last track")
        model.previousTrack()
        await run(3, "previous, early in track")
        await run(2, "keeps playing")
        model.previousTrack()
        await run(3, "previous, 4 s in")
        model.togglePlay()
        await run(2, "pause pressed")
        model.togglePlay()
        await run(2, "play pressed")
        model.startStop()
        await run(2, "stop button")
        model.startStop()
        await run(3, "start button")
        // Carry the arm to the middle of the record and drop it.
        let grab = model.geometry.pivot + model.geometry.armDirection(swing: scene.currentSwing) * 0.2
        if model.beginDrag(at: grab, currentSwing: scene.currentSwing) {
            await run(0.5, "arm lifted")
            let swing = model.geometry.swing(forProgress: 0.5)
            model.drag(to: model.geometry.pivot + model.geometry.armDirection(swing: swing) * 0.2)
            model.endDrag()
        }
        await run(3, "dropped at 0.5")
        if model.beginDrag(at: model.geometry.pivot + model.geometry.armDirection(swing: scene.currentSwing) * 0.2, currentSwing: scene.currentSwing) {
            let swing = model.geometry.swing(forProgress: 0.9985)
            model.drag(to: model.geometry.pivot + model.geometry.armDirection(swing: swing) * 0.2)
            model.endDrag()
        }
        await run(1.5, "dropped near the end")
        await run(2, "after the record ends")
        let silent = TurntableModel(spec: model.spec, record: .placeholder)
        await labelSwap(to: silent, "returns to the placeholder without a record")
        await labelSwap(to: model, "shows the cover again")
        // A second record at rest asks for another cover; switching straight back must not let it win.
        if let other = LocalPlayback.testLibrary() {
            other.playback.isMuted = true
            other.playback.load(other.records[1])
            scene.update(deltaTime: 1.0 / 60, model: TurntableModel(spec: model.spec, playback: other.playback))
            await labelSwap(to: model, "keeps the latest cover after a quick change")
            await run(0.5, "after the quick change")
            check(scene.shownArtworkID == model.nowPlayingArtwork?.id, "the stale cover did not win")
        }
        await recordChangeCheck(model: model, scene: scene, playback: playback, records: library.records)
        print(failures.isEmpty ? "playback check: all assertions passed" : "playback check: FAILED \(failures)")
        if !failures.isEmpty { exit(1) }
    }

    /// Loads other records while playing and while empty, and checks the sound, the arm, the swap and the label.
    private static func recordChangeCheck(
        model: TurntableModel, scene: TurntableScene, playback: LocalPlayback, records: [Record]
    ) async {
        var failures = 0
        func check(_ condition: Bool, _ what: String) {
            print("check:", what, condition ? "ok" : "FAILED")
            if !condition { failures += 1 }
        }
        func run(until done: () -> Bool, limit: Double) async -> Double {
            var elapsed = 0.0
            while !done(), elapsed < limit {
                scene.update(deltaTime: 1.0 / 60, model: model)
                try? await Task.sleep(for: .milliseconds(16))
                elapsed += 1.0 / 60
            }
            return elapsed
        }
        func run(_ seconds: Double) async { _ = await run(until: { false }, limit: seconds) }
        guard records.count > 1 else { return }
        let old = records[0]
        let new = records[1]
        // Start from a known state: the first record, playing track 1.
        if model.record?.id != old.id { model.load(old); _ = await run(until: { model.change == nil }, limit: 20) }
        model.startStop()
        if !model.isNeedleDown { model.togglePlay() }
        await run(3)
        check(model.isPlaying && playback.isPlaying, "playing before the change")

        model.load(new)
        check(model.change != nil, "a change starts")
        let grabbed = model.beginDrag(
            at: model.geometry.pivot + model.geometry.armDirection(swing: scene.currentSwing) * 0.2,
            currentSwing: scene.currentSwing
        )
        model.togglePlay()
        model.nextTrack()
        check(!grabbed && !model.isNeedleDown && !model.isMotorOn, "controls and the arm do nothing during a change")
        check(model.record?.id == old.id, "the old record stays on the platter until it is lifted")
        await run(0.3)
        check(!playback.isPlaying, "the old audio stops")
        var armWasHome = true
        var sawLift = false
        let took = await run(until: {
            if model.change?.phase == .lifting {
                sawLift = true
                armWasHome = armWasHome && abs(scene.currentSwing - model.geometry.restSwing) < 0.011
            }
            return model.change == nil
        }, limit: 12)
        print(String(format: "record change took %.2f s", took))
        check(sawLift && armWasHome, "the arm is home while the record lifts")
        check(model.change == nil, "the change finishes")
        check(model.record?.id == new.id && playback.record?.id == new.id, "the new record is on the platter")
        check(model.layout.trackCount == new.tracks.count, "the layout is the new record's")
        check(model.nowPlaying == nil && !model.isNeedleDown, "the needle is up after the change")
        await run(0.5)
        check(scene.shownArtworkID == new.tracks[0].artwork?.id, "the label shows the new record's cover")

        model.togglePlay()
        await run(2)
        check(model.nowPlaying?.title == new.tracks[0].title && playback.isPlaying, "track 1 of the new record plays")
        check(playback.record?.id == new.id, "the player holds the new record")

        model.load(nil)
        _ = await run(until: { model.change == nil }, limit: 12)
        check(model.record == nil && !playback.isPlaying, "removing the record empties the platter")
        model.togglePlay()
        model.startStop()
        model.play(track: 0)
        await run(1)
        check(!model.isNeedleDown && !playback.isPlaying, "an empty platter does not play")
        let grab = model.geometry.pivot + model.geometry.armDirection(swing: scene.currentSwing) * 0.2
        if model.beginDrag(at: grab, currentSwing: scene.currentSwing) {
            model.drag(to: model.geometry.pivot + model.geometry.armDirection(swing: model.geometry.swing(forProgress: 0.5)) * 0.2)
            model.endDrag()
        }
        await run(2)
        check(!model.isNeedleDown && abs(scene.currentSwing - model.geometry.restSwing) < 0.011, "the arm drops back to rest over an empty platter")

        model.load(old)
        _ = await run(until: { model.change == nil }, limit: 12)
        check(model.record?.id == old.id, "a record loads onto the empty platter")
        await run(0.5)
        check(scene.shownArtworkID == old.tracks[0].artwork?.id, "the label shows that record's cover")
        if failures > 0 {
            print("playback check: FAILED record change")
            exit(1)
        }
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.count > index + 1 else { return nil }
        return arguments[index + 1]
    }

    static func render(
        to url: URL, width: Int, height: Int, view: TurntableCameraView, play: Bool, track: Int, swing: Float?,
        stopAt: (phase: RecordChange.Phase, progress: Float)?, empty: Bool
    ) async throws {
        let library = LocalPlayback.testLibrary()
        let playback = play || stopAt != nil || empty ? library?.playback : nil
        playback?.isMuted = true
        let first = empty ? nil : library?.records.first
        playback?.load(first)
        let model = TurntableModel(playback: playback, record: playback == nil ? .placeholder : first)
        let scene = try await TurntableScene(spec: model.spec, theme: .dark, trackStarts: model.trackStarts)
        scene.show(view, in: CGSize(width: width, height: height), animated: false)

        if let swing {
            // Carry the arm to the requested swing and let go.
            let grab = model.geometry.pivot + model.geometry.armDirection(swing: model.geometry.restSwing) * 0.2
            if model.beginDrag(at: grab, currentSwing: model.geometry.restSwing) {
                model.drag(to: model.geometry.pivot + model.geometry.armDirection(swing: swing) * 0.2)
                model.endDrag()
            }
        } else if play {
            model.togglePlay()
            for _ in 1..<max(1, track) { model.nextTrack() }
        }
        let frames = value(after: "--frames", in: CommandLine.arguments).flatMap(Int.init) ?? 300
        for _ in 0..<frames {
            scene.update(deltaTime: 1.0 / 60, model: model)
        }
        if let stopAt, let library {
            // Swap to the second record and stop partway through the lift or the drop.
            model.load(library.records[1])
            var guardFrames = 0
            while guardFrames < 3000 {
                guardFrames += 1
                scene.update(deltaTime: 1.0 / 60, model: model)
                try await Task.sleep(for: .milliseconds(2))
                if let change = model.change, change.phase == stopAt.phase, change.progress >= stopAt.progress { break }
            }
        }
        // The cover loads in the background: keep running frames until the label shows it.
        let clock = ContinuousClock()
        let start = clock.now
        while stopAt == nil, scene.shownArtworkID != model.nowPlayingArtwork?.id, clock.now - start < .seconds(3) {
            scene.update(deltaTime: 1.0 / 60, model: model)
            try await Task.sleep(for: .milliseconds(16))
        }

        let renderer = try RealityRenderer()
        renderer.entities.append(scene.root)
        renderer.activeCamera = scene.camera
        renderer.cameraSettings.antialiasing = .multisample4X

        guard let device = MTLCreateSystemDefaultDevice() else { throw CocoaError(.featureUnsupported) }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm_srgb, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw CocoaError(.featureUnsupported)
        }

        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        // A few frames, so shadows and lighting have settled.
        for _ in 0..<3 {
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                do {
                    try renderer.updateAndRender(deltaTime: 1.0 / 60, cameraOutput: output) { _ in
                        done.resume()
                    }
                } catch {
                    done.resume()
                }
            }
        }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(
            &pixels,
            bytesPerRow: width * 4,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )
        guard
            let provider = CGDataProvider(data: Data(pixels) as CFData),
            let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
            ),
            let canvas = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil
            )
        else { throw CocoaError(.fileWriteUnknown) }

        canvas.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let composed = canvas.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, composed, nil)
        CGImageDestinationFinalize(destination)
    }
}
#endif
