import SwiftUI

enum AppTab: Hashable { case library, vault, settings, scan, search }

/// Root: content switches by tab; the floating two-pill bar sits over it.
struct RootView: View {
    @State private var tab: AppTab = .library
    @State private var capture = CaptureSession()
    @State private var showScan = false
    @State private var showSearch = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .library: NavigationStack { LibraryView() }
                case .vault: NavigationStack { VaultPlaceholderView() }
                case .settings: NavigationStack { SettingsView() }
                case .scan, .search: NavigationStack { LibraryView() }
                }
            }
            .safeAreaPadding(.bottom, 92)   // room for the floating bar

            FloatingTabBar(tab: $tab, onScan: { showScan = true }, onSearch: { showSearch = true })
        }
        .environment(capture)
        .fullScreenCover(isPresented: $showScan) {
            NavigationStack { ScanHomeView(onDone: { showScan = false }) }
                .environment(capture)
        }
        .sheet(isPresented: $showSearch) {
            NavigationStack { SearchView() }
                .presentationDetents([.large])
        }
        .onChange(of: capture.hasPages) { _, has in
            // Pages arrived while the scan cover is closed (e.g. share sheet in a later phase): open it.
            if has && !showScan { showScan = true }
        }
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

/// Phase 4 replaces this.
struct VaultPlaceholderView: View {
    var body: some View {
        ContentUnavailableView("Vault — coming in Phase 4",
                               systemImage: "lock.shield",
                               description: Text("Sensitive documents will be stored here behind Face ID."))
        .navigationTitle("Vault")
        .background(Theme.Colors.canvas)
    }
}
