import SwiftUI
import SwiftData
import DocuVaultCore

/// Settings, cut down (checkpoint 17): only what you can change. Keyboard, Documents, Erase, then the
/// version. Read-only facts (OCR mode, storage class, bundle ID, fixed lock times) left the screen.
struct SettingsView: View {
    @Query private var docs: [StoredDocument]
    @Environment(\.modelContext) private var context
    @State private var summaries = SummaryService.shared
    @State private var models = LocalModelManager.shared
    @State private var cloud = CloudService.shared
    @State private var export = ExportManager.shared
    @AppStorage(AppFiles.keyboardLockWindowKey, store: UserDefaults(suiteName: AppFiles.appGroupID))
    private var keyboardLockWindow: Double = AppFiles.keyboardLockWindowDefault
    @AppStorage(AppFiles.keyboardStartPageKey, store: UserDefaults(suiteName: AppFiles.appGroupID))
    private var keyboardStartPage: String = AppFiles.KeyboardStartPage.recents.rawValue

    var body: some View {
        CardPage {
            CardSection(title: "Keyboard") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Stays unlocked").font(.system(size: 17, weight: .semibold))
                    Picker("Stays unlocked", selection: $keyboardLockWindow) {
                        Text("Immediately").tag(0.0)
                        Text("1 min").tag(60.0)
                        Text("5 min").tag(300.0)
                        Text("15 min").tag(900.0)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                Menu {
                    Picker("Opens on", selection: $keyboardStartPage) {
                        ForEach(AppFiles.KeyboardStartPage.allCases, id: \.rawValue) { Text($0.displayName).tag($0.rawValue) }
                    }
                } label: {
                    CardRow(title: "Opens on", value: AppFiles.KeyboardStartPage(stored: keyboardStartPage)?.displayName, chevron: true)
                }
                .buttonStyle(.plain)
            }

            CardSection(title: "Documents") {
                NavigationLink { SummariesSettingsView() } label: {
                    CardRow(title: "Summaries", subtitle: summariesLine, icon: "text.alignleft", chevron: true)
                }
                .buttonStyle(.plain)
                NavigationLink { ExportView() } label: {
                    CardRow(title: "Export", subtitle: exportLine, icon: "square.and.arrow.up", chevron: true)
                }
                .buttonStyle(.plain)
                NavigationLink { CloudSettingsView() } label: {
                    CardRow(title: "Claude", subtitle: cloud.hasKey ? "On · \(CloudCost.model(cloud.modelID).displayName)" : "Off · Vault documents are never sent",
                            icon: "cloud", tint: Theme.Colors.cloud, chevron: true)
                }
                .buttonStyle(.plain)
            }

            CardSection(title: "Erase") {
                ConfirmRow(title: "Delete all documents", subtitle: "\(docs.count) document\(docs.count == 1 ? "" : "s") and their pages",
                           question: "Every document and page image is deleted.", action: "Delete all") {
                    for d in docs { for p in d.pages { PageStore.delete(p.imageFileName) }; context.delete(d) }
                    try? context.save()
                }
                ConfirmRow(title: "Reset vault key", subtitle: "Sealed documents become unreadable",
                           question: "Every sealed document becomes unreadable. Delete them first.", action: "Reset key") {
                    VaultKeychain.deleteKey()
                }
            }

            Text("DocuVault \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                .font(.system(size: 13)).foregroundStyle(Theme.Colors.ink2)
                .frame(maxWidth: .infinity)
        }
        .navigationTitle("Settings")
    }

    private var summariesLine: String {
        let on = summaries.autoSummarise ? "On" : "Off"
        switch models.state {
        case .installed, .ready, .loading: return "\(on) · Chinese model installed"
        case .downloading(let r, let t): return "\(on) · Chinese model \(t > 0 ? Int(Double(r) / Double(t) * 100) : 0)%"
        case .paused, .failed: return "\(on) · Chinese model paused"
        case .verifying: return "\(on) · Chinese model checking"
        case .unavailable(let why): return "\(on) · \(why)"
        case .notInstalled: return "\(on) · Chinese model not installed"
        }
    }

    private var exportLine: String {
        guard let d = export.lastExport else { return export.syncFolder ? "Folder sync on" : "Not exported yet" }
        return "Last \(d.dvDisplay(time: true))"
    }
}

/// Summaries: the one switch, Apple's model for English, and the Chinese model with its install,
/// download and Try it states (checkpoint 18).
struct SummariesSettingsView: View {
    @State private var summaries = SummaryService.shared

    var body: some View {
        CardPage {
            CardSection {
                CardToggle(title: "Summarise contracts and letters", subtitle: "When you save one",
                           isOn: Binding(get: { summaries.autoSummarise }, set: { summaries.autoSummarise = $0 }))
            }
            CardSection(title: "English") {
                CardRow(title: "Apple Intelligence", subtitle: AppleSummarizer.availability.message,
                        icon: (AppleSummarizer.availability == .available) ? "checkmark" : "xmark",
                        tint: (AppleSummarizer.availability == .available) ? Theme.Colors.verified : Theme.Colors.ink)
            }
            ChineseModelSection()
        }
        .navigationTitle("Summaries")
        .navigationBarTitleDisplayMode(.inline)
    }
}
