import SwiftUI
import SwiftData

@main
struct DocuVaultApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try AppFiles.makeContainer()
        } catch {
            fatalError("Could not open the DocuVault store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Theme.Colors.accent)   // iOS back arrows, Cancel, Save and menus follow the gunmetal
        }
        .modelContainer(container)
        // iOS relaunches the app in the background to hand over a finished model download (checkpoint 18).
        .backgroundTask(.urlSession(ModelDownloader.sessionID)) {
            await ModelDownloader.shared.handleBackgroundEvents()
        }
    }
}
