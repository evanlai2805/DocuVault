import SwiftUI

struct RootView: View {
    @State private var showImport = false
    @State private var capture = CaptureSession()

    var body: some View {
        TabView {
            Tab("Library", systemImage: "doc.text") {
                NavigationStack { LibraryView() }
            }
            Tab("Scan", systemImage: "camera.viewfinder") {
                NavigationStack { ScanHomeView() }
            }
            Tab("Vault", systemImage: "lock.shield") {
                NavigationStack { VaultPlaceholderView() }
            }
            Tab("Settings", systemImage: "gearshape") {
                NavigationStack { SettingsView() }
            }
        }
        .environment(capture)
    }
}

/// Phase 4 replaces this.
struct VaultPlaceholderView: View {
    var body: some View {
        ContentUnavailableView("Vault — coming in Phase 4",
                               systemImage: "lock.shield",
                               description: Text("Sensitive documents will be stored here behind Face ID."))
        .navigationTitle("Vault")
    }
}
