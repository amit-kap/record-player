import SwiftUI

/// The camera views as a strip of thumbnails along the bottom. Click one or press 1, 2 or 3.
struct HUDViewStrip: View {
    @Binding var cameraView: TurntableCameraView
    let hide: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(TurntableCameraView.allCases.enumerated()), id: \.element) { index, view in
                HUDViewCard(view: view, number: index + 1, isSelected: view == cameraView) {
                    cameraView = view
                }
            }
            HUDButton(symbol: "chevron.down", size: 10, label: "Hide views", help: "Hide views (V)", side: 24, action: hide)
                .hudGlass(radius: 8)
        }
        // The hide button hangs off the right, so the three views stay centred.
        .padding(.leading, 34)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Camera view")
    }
}

/// One view: a render of the deck from there, with its key and name underneath.
private struct HUDViewCard: View {
    let view: TurntableCameraView
    let number: Int
    let isSelected: Bool
    let select: () -> Void

    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button(action: select) {
            VStack(spacing: 0) {
                thumbnail
                    .frame(width: HUDLayout.thumbnail.width, height: HUDLayout.thumbnail.height)
                    .clipped()
                    .opacity(isSelected ? 1 : isHovered ? 0.85 : 0.6)
                HStack(spacing: 8) {
                    Text("\(number)")
                    Text(view.title)
                    Spacer()
                }
                .hudLabelStyle(isSelected ? 1 : isHovered ? 0.75 : 0.5)
                .foregroundStyle(isSelected ? Color.hudAccent : .white.opacity(isHovered ? 0.75 : 0.5))
                .padding(.horizontal, 10)
                .frame(height: 24)
            }
            .frame(width: HUDLayout.thumbnail.width)
            .hudGlass(radius: 8)
            .clipShape(shape)
            .overlay(shape.strokeBorder(isSelected ? Color.hudAccent : .white.opacity(0.1), lineWidth: isSelected ? 1 : 0.5))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .help("\(view.title) view (\(number))")
        .accessibilityLabel("\(view.title) view")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private var thumbnail: some View {
        if let image = HUDThumbnails.image(for: view) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Color.white.opacity(0.06)
        }
    }
}

/// The renders of the deck from each view, bundled as `view-top.png`, `view-side.png` and `view-tonearm.png`.
@MainActor
private enum HUDThumbnails {
    private static let images: [TurntableCameraView: NSImage] = Dictionary(
        uniqueKeysWithValues: TurntableCameraView.allCases.compactMap { view in
            Bundle.main.url(forResource: "view-\(view.rawValue)", withExtension: "png")
                .flatMap(NSImage.init(contentsOf:))
                .map { (view, $0) }
        }
    )

    static func image(for view: TurntableCameraView) -> NSImage? { images[view] }
}
