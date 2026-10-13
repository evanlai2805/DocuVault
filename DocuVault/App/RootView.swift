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
    @State private var confirmDiscard = false

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
            // Room for the floating bar. Content margins travel through the environment, so pages pushed
            // inside a tab get them too; the old safeAreaInset reached only each tab's first page, and the
            // last row or two of every pushed page sat under the bar (Evan, 13 Oct; checked in a Simulator
            // probe). Lists ignore these margins, so no List sits under the bar: those screens are cards.
            .contentMargins(.bottom, FloatingTabBar.contentClearance, for: .scrollContent)

            if let selection = chrome.selection {
                SelectionBar(model: selection)
            } else {
                FloatingTabBar(tab: $tab, onScan: { showScan = true }, onSearch: { showSearch = true })
            }

        }
        .overlay {
            // Privacy shield in the app switcher while the vault is open.
            if scenePhase != .active && vault.isUnlocked && !vault.isAuthenticating {
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                    .overlay(Image(systemName: "lock.shield.fill").font(.system(size: 48)).foregroundStyle(Theme.Colors.ink2))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            vault.sceneDidChange(phase)
            if phase == .active { RetentionManager.sweep(context: context); CloudService.shared.prune(context: context) }
        }
        // A sheet, so it swipes down to close (checkpoint 17). With pages captured the swipe asks
        // first, so a stray swipe never loses work.
        .sheet(isPresented: $showScan) {
            NavigationStack { ScanHomeView(onDone: { showScan = false }) }
                .interactiveDismissDisabled(capture.hasPages)
                .background(DismissAttemptObserver { confirmDiscard = true })
                .confirmationDialog(capture.pages.count == 1 ? "Discard 1 page?" : "Discard \(capture.pages.count) pages?",
                                    isPresented: $confirmDiscard, titleVisibility: .visible) {
                    Button("Discard", role: .destructive) { capture.reset(); showScan = false }
                    Button("Keep scanning", role: .cancel) {}
                } message: { Text("They have not been saved.") }
                .environment(capture)
                .environment(vault)
                .environment(chrome)
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

/// Two Liquid Glass pills, sat low like the system tab bar (Photos, Telegram; Evan, 13 Oct).
/// Left: Library · Vault · Settings. Right: Scan (accent) · Search (graphite).
struct FloatingTabBar: View {
    @Binding var tab: AppTab
    let onScan: () -> Void
    let onSearch: () -> Void

    /// Bar height and its gap above the screen's bottom edge, measured from Evan's Photos and Telegram
    /// screenshots (3x): bars 61 to 63pt tall, bottom edge about 20pt above the screen edge.
    static let height: CGFloat = 62
    static let bottomGap: CGFloat = 20
    /// Scroll content clears the bar by 12pt. The home-indicator safe area (34pt) is already counted.
    static let contentClearance: CGFloat = bottomGap + height + 12 - 34

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                tabItem(.library, "Library", "doc.text.fill")
                tabItem(.vault, "Vault", "lock.shield.fill")
                tabItem(.settings, "Settings", "gearshape.fill")
            }
            .padding(4)
            .frame(height: Self.height)
            .glassEffect(.regular, in: Capsule())

            HStack(spacing: 6) {
                actionCircle("camera.viewfinder", primary: true, label: "Scan", action: onScan)
                // White, like the Photos search circle, so it never reads as a second dark button (17b Q2).
                actionCircle("magnifyingglass", primary: false, label: "Search", action: onSearch)
            }
            .padding(5)
            .frame(height: Self.height)
            .glassEffect(.regular, in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.bottom, Self.bottomGap)
        .ignoresSafeArea(.container, edges: .bottom)
    }

    /// Selected: a soft grey pill with an accent icon and label, as in Photos. Others: black.
    private func tabItem(_ t: AppTab, _ title: String, _ icon: String) -> some View {
        let on = tab == t
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { tab = t }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 19, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(on ? Theme.Colors.accent : Theme.Colors.ink)
            .frame(maxWidth: .infinity).frame(height: Self.height - 8)
            .background(on ? Color.black.opacity(0.07) : .clear)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    @ViewBuilder private func actionCircle(_ icon: String, primary: Bool, label: String, action: @escaping () -> Void) -> some View {
        let glyph = Image(systemName: icon)
            .font(.system(size: 20, weight: .semibold))
            .frame(width: Self.height - 10, height: Self.height - 10)
        Button(action: action) {
            if primary {
                glyph.foregroundStyle(.white).accentSheen(in: Circle())
            } else {
                glyph.foregroundStyle(Theme.Colors.ink)
                    .background(Circle().fill(.white))
                    .overlay(Circle().stroke(Theme.Colors.hairline, lineWidth: 0.5))
            }
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
