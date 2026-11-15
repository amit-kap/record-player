import SwiftUI

/// The track under the needle: title, artist, record and elapsed time. Empty while nothing plays.
struct TrackInfoLine: View {
    let model: TurntableModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let track = model.nowPlaying, let record = model.record {
                Text(track.title)
                    .foregroundStyle(.white.opacity(0.88))
                    .layoutPriority(1)
                Text("\(track.artist) · \(record.title)")
                    .foregroundStyle(.white.opacity(0.42))
                Spacer(minLength: 12)
                Text(Self.clock(model.elapsedSeconds))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.6))
                    .layoutPriority(2)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .lineLimit(1)
        .animation(.easeOut(duration: 0.25), value: model.nowPlaying)
        .accessibilityElement(children: .combine)
    }

    static func clock(_ seconds: Int) -> String {
        "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}
