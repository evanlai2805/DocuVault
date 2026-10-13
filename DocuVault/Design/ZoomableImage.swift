import SwiftUI

/// A scan you can pinch to zoom, drag when zoomed, and double-tap to reset. Used by the field edit
/// sheet so Evan can check a value against the page without leaving it (checkpoint 14 Q1).
/// No Theme dependency, so the keyboard can compile it too for its scan view (checkpoint 14 Q2).
struct ZoomableImage: View {
    let image: CGImage
    /// Told whether the page is zoomed in, so a parent can keep swipe-down-to-close for the unzoomed page.
    var onZoomChange: ((Bool) -> Void)? = nil
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .offset(offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                MagnifyGesture()
                    .onChanged { scale = min(max(lastScale * $0.magnification, 1), 6) }
                    .onEnded { _ in
                        lastScale = scale
                        if scale == 1 { offset = .zero; lastOffset = .zero }
                    }
                    .simultaneously(with: DragGesture()
                        .onChanged { v in
                            guard scale > 1 else { return }
                            offset = CGSize(width: lastOffset.width + v.translation.width,
                                            height: lastOffset.height + v.translation.height)
                        }
                        .onEnded { _ in lastOffset = offset })
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    scale = scale > 1 ? 1 : 2.5
                    lastScale = scale
                    offset = .zero
                    lastOffset = .zero
                }
            }
            .clipped()
            .onChange(of: scale > 1) { _, zoomed in onZoomChange?(zoomed) }
            .accessibilityLabel("Scan. Pinch to zoom.")
    }
}
