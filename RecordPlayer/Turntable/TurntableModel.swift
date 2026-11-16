import Observation
import simd
import TurntableCore

/// What the turntable is doing. The 3D scene and the controls both read and drive this.
@MainActor
@Observable
final class TurntableModel {
    /// The record player being shown.
    let spec: TurntableSpec
    var geometry: TurntableGeometry { spec.geometry }
    /// Makes the sound. Nil means a silent turntable.
    @ObservationIgnored private let playback: RecordPlayback?
    /// What sits on the platter. Nil is an empty platter.
    private(set) var record: Record?
    private(set) var layout: RecordLayout

    /// A record being swapped, while the change runs. Controls do nothing until it is over.
    private(set) var change: RecordChange?
    /// The record that is coming, and how it is laid out, while a change runs.
    private var incoming: (record: Record?, layout: RecordLayout)?

    /// Where the tonearm should be.
    private(set) var targetSwing: Float
    /// The needle is meant to be on the record.
    private(set) var isNeedleDown = false
    /// The platter motor. Play/pause switches it and the needle stays where it is.
    private(set) var isMotorOn = false
    private(set) var isDragging = false
    /// The button being held down.
    private(set) var pressedControl: TurntableControl?

    /// The track under the needle, counted from 0.
    private(set) var currentTrack = 0
    /// Whole seconds into the current track.
    private(set) var elapsedSeconds = 0

    /// Where each track starts, as 0...1 between the first and last groove.
    var trackStarts: [Float] { layout.trackStarts }
    /// Where the tracks of the record that is coming start, while a change runs.
    var incomingTrackStarts: [Float]? { incoming?.record == nil ? nil : incoming?.layout.trackStarts }
    /// The cover the label will show for the record that is coming: its first song's.
    var incomingArtwork: Artwork? {
        guard let record = incoming?.record else { return nil }
        return record.tracks.first?.artwork ?? record.artwork
    }

    private var dragOffset: Float = 0
    /// The needle is touching the record, as the scene last reported it.
    private var isNeedleOnRecord = false
    /// Where to start playing when the needle next touches down or the platter next starts.
    private var pendingStart: RecordLayout.Position?

    /// Previous restarts the track when it is further in than this, in seconds.
    private let restartThreshold: Double = 3

    /// `record` is on the platter to begin with; without one, the player's current record.
    init(spec: TurntableSpec = TurntableSpec.all[0], playback: RecordPlayback? = nil, record: Record? = nil) {
        self.spec = spec
        self.playback = playback
        let first = record ?? playback?.record
        self.record = first
        self.layout = RecordLayout(durations: first?.tracks.map(\.duration) ?? [])
        self.targetSwing = spec.geometry.restSwing
        playback?.onRecordEnded = { [weak self] in self?.recordEnded() }
    }

    /// The platter turns while the motor runs under the needle, and as soon as the arm is carried over the record.
    var wantsSpin: Bool {
        (isNeedleDown && isMotorOn) || (isDragging && geometry.isOverRecord(swing: targetSwing))
    }

    /// The needle is down and the platter turns.
    var isPlaying: Bool { isNeedleDown && isMotorOn }

    /// Controls work only with a record on the platter and no change running.
    private var isReady: Bool { record != nil && change == nil }

    /// The track under the needle, or nil on a silent turntable or with the arm at rest.
    var nowPlaying: RecordTrack? {
        guard isNeedleDown, let tracks = record?.tracks, tracks.indices.contains(currentTrack) else { return nil }
        return tracks[currentTrack]
    }

    /// The cover of the track under the needle (or the last one played), else the record's. Nil with no record.
    /// It changes in the same update as `nowPlaying`.
    var nowPlayingArtwork: Artwork? {
        guard let record else { return nil }
        let tracks = record.tracks
        return (tracks.indices.contains(currentTrack) ? tracks[currentTrack].artwork : nil) ?? record.artwork
    }

    // MARK: Tonearm

    /// Starts carrying the tonearm if `point` is on it. Returns false when the press missed the arm.
    func beginDrag(at point: SIMD2<Float>, currentSwing: Float) -> Bool {
        let fromPivot = simd_length(point - geometry.pivot)
        guard change == nil, fromPivot > 0.05,
              geometry.distanceToArm(from: point, swing: currentSwing) < spec.armGrabDistance
        else { return false }
        dragOffset = currentSwing - geometry.swing(toward: point)
        isDragging = true
        isNeedleDown = false
        pendingStart = nil
        targetSwing = currentSwing
        return true
    }

    func drag(to point: SIMD2<Float>) {
        guard isDragging else { return }
        targetSwing = geometry.clampedSwing(geometry.swing(toward: point) + dragOffset)
    }

    /// Lets go of the tonearm: it lands on the record if it is over it, otherwise it goes back to its rest.
    func endDrag() {
        guard isDragging else { return }
        isDragging = false
        if record == nil {
            returnArm()
        } else if geometry.isOverRecord(swing: targetSwing) {
            lowerNeedle()
        } else if targetSwing < geometry.leadInSwing {
            // Inside the last groove: settle on the last groove.
            targetSwing = geometry.leadOutSwing
            lowerNeedle()
        } else {
            returnArm()
        }
    }

    private func lowerNeedle() {
        isNeedleDown = true
        isMotorOn = true
        let start = layout.position(forProgress: geometry.progress(swing: targetSwing))
        pendingStart = start
        showPosition(start)
    }

    private func returnArm() {
        isNeedleDown = false
        isMotorOn = false
        pendingStart = nil
        targetSwing = geometry.restSwing
    }

    // MARK: Controls

    /// The start/stop button on the plinth. With the arm at rest it plays from the first groove; with the needle
    /// down it lifts the needle and sends the arm home.
    func startStop() {
        guard !isDragging, isReady else { return }
        if isNeedleDown {
            returnArm()
        } else {
            play(track: 0)
        }
    }

    /// Play/pause, for the keyboard and the media keys. With the needle down it stops and starts the platter and
    /// keeps the place; with the arm at rest it plays from the first groove.
    func togglePlay() {
        guard !isDragging, isReady else { return }
        if isNeedleDown {
            isMotorOn.toggle()
        } else {
            play(track: 0)
        }
    }

    /// Moves the needle to the start of the next track.
    func nextTrack() {
        guard !isDragging, isReady, isNeedleDown, currentTrack + 1 < layout.trackCount else { return }
        play(track: currentTrack + 1)
    }

    /// Moves the needle back to the start of this track, or of the one before when this one has only just begun.
    func previousTrack() {
        guard !isDragging, isReady, isNeedleDown else { return }
        let time = playback.map { $0.trackIndex == currentTrack ? $0.time : 0 } ?? Double(elapsedSeconds)
        play(track: time > restartThreshold ? currentTrack : max(currentTrack - 1, 0))
    }

    /// Moves the needle to the start of a track and plays it, from rest too.
    func play(track: Int) {
        guard !isDragging, isReady, (0..<layout.trackCount).contains(track) else { return }
        let start = RecordLayout.Position(track: track, time: 0)
        targetSwing = geometry.swing(forProgress: layout.progress(track: track, time: 0))
        isNeedleDown = true
        isMotorOn = true
        pendingStart = start
        showPosition(start)
    }

    // MARK: Changing the record

    /// Puts `record` on the platter, or empties it with nil. A record already there is sent off first: the arm goes
    /// home, the platter stops and the sound ends; then the scene lifts the old record off and drops the new one on.
    /// Does nothing while a change runs, or for the record that is already there.
    func load(_ record: Record?) {
        guard change == nil, !isDragging, record?.id != self.record?.id else { return }
        playback?.pause()
        returnArm()
        incoming = (record, RecordLayout(durations: record?.tracks.map(\.duration) ?? []))
        change = RecordChange(hasOutgoing: self.record != nil, hasIncoming: record != nil)
    }

    /// Moves a change on. The scene calls it every frame, because it knows whether the arm is home, whether the
    /// platter has stopped and whether the incoming record's grooves are built.
    func advanceChange(by dt: Float, armIsHome: Bool, platterIsStopped: Bool, incomingIsReady: Bool) {
        guard var running = change, let incoming else { return }
        let events = running.advance(
            by: dt, armIsHome: armIsHome, platterIsStopped: platterIsStopped, incomingIsReady: incomingIsReady
        )
        change = events.contains(.finished) ? nil : running
        if events.contains(.swap) {
            record = incoming.record
            layout = incoming.layout
            currentTrack = 0
            elapsedSeconds = 0
            pendingStart = nil
            playback?.load(incoming.record)
        }
        if events.contains(.finished) { self.incoming = nil }
    }

    private func recordEnded() {
        guard !isDragging else { return }
        returnArm()
    }

    private func showPosition(_ position: RecordLayout.Position) {
        if currentTrack != position.track { currentTrack = position.track }
        let seconds = Int(position.time)
        if elapsedSeconds != seconds { elapsedSeconds = seconds }
    }

    // MARK: Frame updates

    /// Called every frame by the scene, which knows whether the needle has actually reached the record.
    func advance(needleOnRecord: Bool) {
        isNeedleOnRecord = needleOnRecord
        let shouldSound = needleOnRecord && isNeedleDown && isMotorOn && !isDragging

        guard let playback else {
            // Silent turntable: nothing moves the arm inward, the needle just sits in its groove.
            return
        }
        if shouldSound {
            if let start = pendingStart {
                // The needle has just landed, or the platter has just started again.
                pendingStart = nil
                playback.play(track: start.track, at: start.time)
            }
            // The needle follows the music inward.
            let position = RecordLayout.Position(track: playback.trackIndex, time: playback.time)
            targetSwing = geometry.swing(forProgress: layout.progress(track: position.track, time: position.time))
            showPosition(position)
        } else if playback.isPlaying {
            // A stopped platter keeps its place; a lifted arm starts again from wherever it lands.
            if isNeedleDown, !isDragging, pendingStart == nil {
                pendingStart = RecordLayout.Position(track: playback.trackIndex, time: playback.time)
            }
            playback.pause()
        }
    }

    // MARK: Buttons

    /// Presses the button under `point`, if there is one.
    func press(at point: SIMD2<Float>) {
        pressedControl = spec.control(at: point)
    }

    /// Lets the held button go without it acting.
    func cancelPress() {
        pressedControl = nil
    }

    /// Lets the held button go. It acts only if the pointer is still on it.
    func release(at point: SIMD2<Float>) {
        guard let control = pressedControl else { return }
        pressedControl = nil
        guard spec.contains(point, in: control) else { return }
        switch control {
        case .startStop: startStop()
        case .previous: previousTrack()
        case .next: nextTrack()
        }
    }
}
