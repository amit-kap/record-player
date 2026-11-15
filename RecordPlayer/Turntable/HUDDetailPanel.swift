import SwiftUI

/// The full-height panel on the left: the cover, the song under the needle, its controls and the record's tracks.
/// Press H or its button to hide it.
struct HUDDetailPanel: View {
    let model: TurntableModel
    let hide: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let contentWidth = HUDLayout.detailWidth - 2 * HUDLayout.detailPadding

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 10)
            HUDCover(artwork: artwork, side: Self.contentWidth)
                .padding(.bottom, 16)
            info
                .padding(.bottom, 16)
            progress
                .padding(.bottom, 12)
            transport
            HUDTrackList(model: model)
                .padding(.top, 14)
            loadRecord
                .padding(.bottom, 12)
            HUDRecordDetails(record: model.record)
        }
        .padding(HUDLayout.detailPadding)
        .frame(width: HUDLayout.detailWidth)
        .frame(maxHeight: .infinity)
        .hudGlass()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Player")
    }

    // MARK: Load

    @State private var showsLoadNote = false

    /// Where a record will be picked. Until Apple Music is wired in it only says so.
    private var loadRecord: some View {
        Button {
            showsLoadNote = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                Text("Load record")
                    .hudLabelStyle(0.8)
            }
            .foregroundStyle(.white.opacity(0.8))
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsLoadNote, arrowEdge: .leading) {
            Text("Picking albums and playlists arrives with Apple Music.")
                .font(.system(size: 12))
                .padding(12)
        }
    }

    // MARK: Header

    /// What the turntable is doing, and the button that hides the panel.
    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.isPlaying ? Color.hudAccent : .white.opacity(0.25))
                .frame(width: 5, height: 5)
            Text(state)
                .hudLabelStyle(0.6)
            Spacer()
            HUDButton(
                symbol: "sidebar.right", size: 11, label: "Hide playback", help: "Hide playback (H)", side: 24,
                action: hide
            )
        }
        .frame(height: 24)
        .padding(.trailing, -4)
        .accessibilityElement(children: .contain)
    }

    private var state: String {
        guard model.nowPlaying != nil else { return "Ready" }
        return model.isPlaying ? "Now playing" : "Paused"
    }

    // MARK: Song

    private var artwork: Artwork? {
        model.nowPlaying == nil ? model.record?.artwork ?? model.nowPlayingArtwork : model.nowPlayingArtwork
    }

    /// Title, artist and album, read by VoiceOver as one line.
    private var info: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(model.record == nil ? 0.5 : 0.95))
                .minimumScaleFactor(0.7)
                .help(title)
            if let artist {
                Text(artist)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            if let album {
                Text(album)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.42))
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.2), value: model.nowPlaying)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary)
    }

    private var title: String {
        model.nowPlaying?.title ?? model.record?.title ?? "No record on the platter"
    }

    private var artist: String? {
        model.nowPlaying?.artist ?? model.record?.artist
    }

    private var album: String? { model.nowPlaying?.album }

    private var spokenSummary: String {
        if let track = model.nowPlaying {
            let state = model.isPlaying ? "Playing" : "Paused"
            return "\(state): \(track.title), by \(track.artist), from \(track.album). "
                + "\(clock(model.elapsedSeconds)) of \(clock(Int(track.duration.rounded())))"
        }
        guard let record = model.record else { return "No record on the platter" }
        return "On the platter: \(record.title), by \(record.artist). Not playing"
    }

    // MARK: Progress

    /// A thin line for the current track, with elapsed and length under it. The seconds hold their width, so
    /// nothing shifts as they tick.
    private var progress: some View {
        let track = model.nowPlaying
        let length = track.map { Int($0.duration.rounded()) }
        let fraction = length.map { $0 > 0 ? min(Double(model.elapsedSeconds) / Double($0), 1) : 0 } ?? 0
        return VStack(spacing: 8) {
            Rectangle()
                .fill(.white.opacity(0.14))
                .frame(height: 2)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.hudAccent)
                        .scaleEffect(x: fraction, anchor: .leading)
                        // A new track starts from the left at once instead of sweeping back.
                        .id(model.currentTrack)
                        .animation(reduceMotion || !model.isPlaying ? nil : .linear(duration: 1), value: fraction)
                }
                .clipShape(Capsule())
            HStack {
                Text(track == nil ? "-:--" : clock(model.elapsedSeconds))
                    .foregroundStyle(.white.opacity(track == nil ? 0.3 : 0.8))
                Spacer()
                Text(length.map(clock) ?? "-:--")
                    .foregroundStyle(.white.opacity(0.4))
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced).monospacedDigit())
        }
        .accessibilityHidden(true)
    }

    // MARK: Transport

    /// The same actions as space and the arrow keys.
    private var transport: some View {
        let isLoaded = model.record != nil && !model.isDragging
        let isOnRecord = isLoaded && model.isNeedleDown
        return HStack(spacing: 20) {
            HUDButton(
                symbol: "backward.fill", size: 13, label: "Previous track", help: "Previous track (←)", side: 36
            ) {
                model.previousTrack()
            }
            .disabled(!isOnRecord)
            Button {
                model.togglePlay()
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(HUDPlayButtonStyle())
            .disabled(!isLoaded)
            .help("Play or pause (space)")
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
            HUDButton(
                symbol: "forward.fill", size: 13, label: "Next track", help: "Next track (→)", side: 36
            ) {
                model.nextTrack()
            }
            .disabled(!isOnRecord || model.currentTrack + 1 >= model.layout.trackCount)
        }
        .frame(maxWidth: .infinity)
    }
}

/// 75 seconds becomes "1:15".
func clock(_ seconds: Int) -> String {
    "\(seconds / 60):" + String(format: "%02d", seconds % 60)
}

/// The play button: a light disc with a dark symbol, the one solid shape in the panel.
private struct HUDPlayButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Color.black.opacity(0.85) : .white.opacity(0.2))
            .background(Circle().fill(.white.opacity(fill(pressed: configuration.isPressed))))
            .contentShape(Circle())
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }

    private func fill(pressed: Bool) -> Double {
        guard isEnabled else { return 0.08 }
        if pressed { return 0.7 }
        return isHovered ? 1 : 0.9
    }
}

// MARK: Cover

/// The cover as a square, loaded at the screen's pixel size, with small corner marks. It keeps the last cover until
/// the next one is ready, then crossfades.
private struct HUDCover: View {
    let artwork: Artwork?
    let side: CGFloat

    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: (id: String, image: CGImage)?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        shape
            .fill(.white.opacity(0.06))
            .overlay {
                if let shown {
                    Image(decorative: shown.image, scale: displayScale)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .id(shown.id)
                        .transition(.opacity)
                } else {
                    Image(systemName: "opticaldisc")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.white.opacity(0.2))
                }
            }
            .clipShape(shape)
            .overlay(HUDCornerTicks().stroke(.white.opacity(0.55), lineWidth: 1).padding(7))
            .overlay(shape.strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
            .frame(width: side, height: side)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: shown?.id)
            .task(id: "\(artwork?.id ?? "")@\(pixels)") {
                guard let artwork, let loaded = await artwork.image(pixels: pixels), !Task.isCancelled else { return }
                shown = (artwork.id, loaded)
            }
            .accessibilityHidden(true)
    }

    private var pixels: Int { Int((side * displayScale).rounded(.up)) }
}

/// Four small right angles, one in each corner of its frame.
private struct HUDCornerTicks: Shape {
    var length: CGFloat = 9

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (corner, dx, dy) in [
            (CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0), (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
            (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0), (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0),
        ] {
            path.move(to: CGPoint(x: corner.x + dx * length, y: corner.y))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * length))
        }
        return path
    }
}

// MARK: Tracks

/// The record's tracks: number, title and length. The track under the needle is marked. A click on a row
/// moves the needle to that track.
private struct HUDTrackList: View {
    let model: TurntableModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let rowHeight: CGFloat = 28
    private static let rowInset: CGFloat = 8

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(.white.opacity(0.1)).frame(height: 0.5)
            ScrollViewReader { reader in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(Array((model.record?.tracks ?? []).enumerated()), id: \.offset) { index, track in
                            Button {
                                model.play(track: index)
                            } label: {
                                row(number: index + 1, track: track, isCurrent: isCurrent(index))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(index)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: model.currentTrack) {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                        reader.scrollTo(model.currentTrack, anchor: .center)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tracks")
    }

    private func isCurrent(_ index: Int) -> Bool {
        model.nowPlaying != nil && index == model.currentTrack
    }

    private func row(number: Int, track: RecordTrack, isCurrent: Bool) -> some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                if isCurrent {
                    Image(systemName: "waveform")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.hudAccent)
                        .symbolEffect(.variableColor.iterative, isActive: model.isPlaying && !reduceMotion)
                } else {
                    Text(String(format: "%02d", number))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .frame(width: 18, alignment: .leading)
            Text(track.title)
                .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                .foregroundStyle(.white.opacity(isCurrent ? 0.95 : 0.62))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(clock(Int(track.duration.rounded())))
                .font(.system(size: 11, weight: .medium, design: .monospaced).monospacedDigit())
                .foregroundStyle(.white.opacity(isCurrent ? 0.7 : 0.38))
        }
        .padding(.horizontal, Self.rowInset)
        .frame(height: Self.rowHeight)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.white.opacity(isCurrent ? 0.07 : 0)))
        .padding(.horizontal, -Self.rowInset)
        .animation(.easeOut(duration: 0.2), value: isCurrent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(number), \(track.title), \(clock(Int(track.duration.rounded())))")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

// MARK: Details

/// Track count, total length and platter speed, each with its icon.
private struct HUDRecordDetails: View {
    let record: Record?

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(.white.opacity(0.1)).frame(height: 0.5)
            HStack(spacing: 0) {
                if let record {
                    detail("list.bullet", "\(record.tracks.count) " + (record.tracks.count == 1 ? "track" : "tracks"))
                    Spacer(minLength: 8)
                    detail("clock", clock(Int(record.tracks.map(\.duration).reduce(0, +).rounded())))
                    Spacer(minLength: 8)
                }
                detail("opticaldisc", "33⅓ RPM")
            }
            .padding(.top, 12)
        }
        .accessibilityElement(children: .combine)
    }

    private func detail(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
            Text(text)
                .hudLabelStyle(0.55)
                .tracking(0.6)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
    }
}
