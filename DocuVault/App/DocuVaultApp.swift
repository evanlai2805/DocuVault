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
        }
        .modelContainer(container)
    }
}
