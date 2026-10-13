import SwiftUI

/// Screen-wide chrome a child screen can take over. Select mode in the Library swaps the floating tab
/// bar for an action bar, as Files does (checkpoint 16).
@MainActor @Observable
final class AppChrome {
    var selection: SelectionBar.Model?
}

/// Share · Export CSV · Move · Delete for the selected documents. Export CSV shows only when every
/// selected document is a receipt.
struct SelectionBar: View {
    struct Model {
        var count: Int
        var shareText: String
        var csvURL: URL?
        var move: () -> Void
        var delete: () -> Void
    }
    let model: Model

    var body: some View {
        HStack(spacing: 0) {
            ShareLink(item: model.shareText) { item("Share", "square.and.arrow.up") }
                .disabled(model.count == 0)
            if let csv = model.csvURL {
                ShareLink(item: csv) { item("Export CSV", "tablecells") }
            }
            Button(action: model.move) { item("Move", "folder") }.disabled(model.count == 0)
            Button(action: model.delete) { item("Delete", "trash", tint: Theme.Colors.danger) }.disabled(model.count == 0)
        }
        .buttonStyle(.plain)
        .opacity(model.count == 0 ? 0.5 : 1)
        .padding(4)
        .frame(height: FloatingTabBar.height)
        .glassEffect(.regular, in: Capsule())
        .padding(.horizontal, 14)
        .padding(.bottom, FloatingTabBar.bottomGap)
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private func item(_ title: String, _ icon: String, tint: Color = Theme.Colors.accent) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 20, weight: .semibold))
            Text(title).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity).frame(height: FloatingTabBar.height - 8)
        .contentShape(Rectangle())
    }
}
