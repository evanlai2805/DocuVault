import SwiftUI

/// 1Password's Large type (checkpoint 16): one character per box with its position, for reading a
/// number aloud or typing it on another device. Letters in light blue, digits in white, so O and 0
/// never get confused. Shown in-app only; closes when the vault locks.
struct LargeTypeView: View {
    struct Item: Identifiable {
        let label: String
        let value: String
        var id: String { label + value }
    }
    let item: Item
    @Environment(\.dismiss) private var dismiss
    @Environment(VaultSession.self) private var vault
    @State private var drag: CGFloat = 0

    private var chars: [Character] { Array(item.value) }

    var body: some View {
        GeometryReader { geo in
            let columns = geo.size.width > geo.size.height ? max(min(chars.count, 12), 1) : 4
            VStack(spacing: 20) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 36, height: 36).background(.white.opacity(0.14)).clipShape(Circle())
                    }
                    .accessibilityLabel("Close")
                }
                Spacer(minLength: 0)
                Text(item.label).font(.system(size: 15)).foregroundStyle(.white.opacity(0.7))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
                    ForEach(Array(chars.enumerated()), id: \.offset) { i, c in
                        VStack(spacing: 2) {
                            Text(c == " " ? "␣" : String(c))
                                .font(.system(size: 44, weight: .bold))
                                .foregroundStyle(c.isLetter ? Color(red: 0x8F/255, green: 0xB3/255, blue: 0xFF/255) : .white)
                                .minimumScaleFactor(0.5).lineLimit(1)
                            Text("\(i + 1)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                Spacer(minLength: 0)
                Text("Turn the phone sideways for one line").font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
            }
            .padding(20)
        }
        .background(LinearGradient(colors: [Theme.Colors.graphite, Color(red: 0x2C/255, green: 0x2C/255, blue: 0x2E/255)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea())
        .offset(y: drag)
        // Swipe down closes it, like a sheet (checkpoint 17).
        .gesture(
            DragGesture(minimumDistance: 20)
                .onChanged { v in drag = max(0, v.translation.height) }
                .onEnded { v in
                    if v.translation.height > 120 { dismiss() }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { drag = 0 }
                }
        )
        .onChange(of: vault.isUnlocked) { _, unlocked in if !unlocked { dismiss() } }
    }
}
