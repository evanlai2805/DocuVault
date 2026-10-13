import SwiftUI
import UniformTypeIdentifiers

enum AppTab: Hashable { case library, vault, settings, scan, search }

/// Root: content switches by tab; the floating two-pill bar sits over it.
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @State private var tab: AppTab = .library
    @State private var capture = CaptureSession()
    @State private var vault = VaultSession()
    @State private var chrome = AppChrome()
    @State private var showScan = false
    @State private var showSearch = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .library: NavigationStack { LibraryView() }
                case .vault: NavigationStack { VaultView() }
                case .settings: NavigationStack { SettingsView() }
                case .scan, .search: NavigationStack { LibraryView() }
                }
            }
            // Room for the floating bar. safeAreaInset rather than safeAreaPadding: Settings is a List,
            // and a List ignored the padding, so its last rows stayed under the bar.
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 92) }

            if let selection = chrome.selection {
                SelectionBar(model: selection)
            } else {
                FloatingTabBar(tab: $tab, onScan: { showScan = true }, onSearch: { showSearch = true })
            }

        }
        .overlay {
            // Privacy shield in the app switcher while the vault is open.
            if scenePhase != .active && vault.isUnlocked {
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                    .overlay(Image(systemName: "lock.shield.fill").font(.system(size: 48)).foregroundStyle(Theme.Colors.ink2))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            vault.sceneDidChange(phase)
            if phase == .active { RetentionManager.sweep(context: context); CloudService.shared.prune(context: context) }
        }
        .fullScreenCover(isPresented: $showScan) {
            NavigationStack { ScanHomeView(onDone: { showScan = false }) }
        }
        .sheet(isPresented: $showSearch) {
            NavigationStack { SearchView() }
                .presentationDetents([.large])
        }
        .onChange(of: capture.hasPages) { _, has in
            // Pages arrived while the scan cover is closed (e.g. share sheet in a later phase): open it.
            if has && !showScan { showScan = true }
        }
        // Last in the chain so the scan cover and search sheet inherit both sessions too.
        .environment(capture)
        .environment(vault)
        .environment(chrome)
    }
}

/// Two glass pills. Left: Library · Vault · Settings. Right: Scan (accent) · Search (graphite).
struct FloatingTabBar: View {
    @Binding var tab: AppTab
    let onScan: () -> Void
    let onSearch: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                tabItem(.library, "Library", "doc.text.fill")
                tabItem(.vault, "Vault", "lock.shield.fill")
                tabItem(.settings, "Settings", "gearshape.fill")
            }
            .padding(4)
            .frame(height: 68)
            .background(.ultraThinMaterial)
            .overlay(Capsule().stroke(Theme.Colors.hairline.opacity(0.6)))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.12), radius: 14, y: 6)

            HStack(spacing: 6) {
                actionCircle("camera.viewfinder", fill: Theme.Colors.accent, label: "Scan", action: onScan)
                actionCircle("magnifyingglass", fill: Theme.Colors.graphite, label: "Search", action: onSearch)
            }
            .padding(5)
            .frame(height: 68)
            .background(.ultraThinMaterial)
            .overlay(Capsule().stroke(Theme.Colors.hairline.opacity(0.6)))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private func tabItem(_ t: AppTab, _ title: String, _ icon: String) -> some View {
        let on = tab == t
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { tab = t }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(on ? Theme.Colors.accent : Theme.Colors.ink)
            .frame(maxWidth: .infinity).frame(height: 60)
            .background(on ? Theme.Colors.accent.opacity(0.12) : .clear)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func actionCircle(_ icon: String, fill: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(fill)
                .clipShape(Circle())
        }
        .buttonStyle(.pressScale)
        .accessibilityLabel(label)
    }
}

/// Clipboard helper: vault copies expire after 60 s and are kept out of Universal Clipboard.
enum Clipboard {
    static func copy(_ text: String, sensitive: Bool) {
        if sensitive {
            UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: text]],
                                          options: [.expirationDate: Date().addingTimeInterval(60), .localOnly: true])
        } else {
            UIPasteboard.general.string = text
        }
    }
}
