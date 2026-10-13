import SwiftUI
import SwiftData
import DocuVaultCore

/// Settings, cut down (checkpoint 17): only what you can change. Keyboard, Documents, Erase, then the
/// version. Read-only facts (OCR mode, storage class, bundle ID, fixed lock times) left the screen.
struct SettingsView: View {
    @Query private var docs: [StoredDocument]
    @Environment(\.modelContext) private var context
    @State private var confirmWipe = false
    @State private var confirmResetKey = false
    @State private var summaries = SummaryService.shared
    @State private var models = LocalModelManager.shared
    @State private var cloud = CloudService.shared
    @State private var export = ExportManager.shared
    @AppStorage(AppFiles.keyboardLockWindowKey, store: UserDefaults(suiteName: AppFiles.appGroupID))
    private var keyboardLockWindow: Double = AppFiles.keyboardLockWindowDefault
    @AppStorage(AppFiles.keyboardStartPageKey, store: UserDefaults(suiteName: AppFiles.appGroupID))
    private var keyboardStartPage: String = AppFiles.KeyboardStartPage.suggestions.rawValue

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
                    CardRow(title: "Opens on", value: AppFiles.KeyboardStartPage(rawValue: keyboardStartPage)?.displayName, chevron: true)
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
                Button { confirmWipe = true } label: {
                    CardRow(title: "Delete all documents", subtitle: "\(docs.count) document\(docs.count == 1 ? "" : "s") and their pages", destructive: true)
                }
                .buttonStyle(.plain)
                Button { confirmResetKey = true } label: {
                    CardRow(title: "Reset vault key", subtitle: "Sealed documents become unreadable", destructive: true)
                }
                .buttonStyle(.plain)
            }

            Text("DocuVault \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                .font(.system(size: 13)).foregroundStyle(Theme.Colors.ink2)
                .frame(maxWidth: .infinity)
        }
        .navigationTitle("Settings")
        .confirmationDialog("Reset the vault key? Every sealed document becomes unreadable. Delete them first.", isPresented: $confirmResetKey, titleVisibility: .visible) {
            Button("Reset key", role: .destructive) { VaultKeychain.deleteKey() }
        }
        .confirmationDialog("Delete every document and page image?", isPresented: $confirmWipe, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) {
                for d in docs { for p in d.pages { PageStore.delete(p.imageFileName) }; context.delete(d) }
                try? context.save()
            }
        }
    }

    private var summariesLine: String {
        let on = summaries.autoSummarise ? "On" : "Off"
        switch models.state {
        case .installed, .ready, .loading: return "\(on) · Chinese model installed"
        case .downloading: return "\(on) · Chinese model downloading"
        default: return "\(on) · Chinese model not installed"
        }
    }

    private var exportLine: String {
        guard let d = export.lastExport else { return export.syncFolder ? "Folder sync on" : "Not exported yet" }
        return "Last \(d.dvDisplay(time: true))"
    }
}

/// Summaries: the one switch and which model runs on this phone for each language. The install flow for
/// the Chinese model is checkpoint 18; here it only moved out of Settings.
struct SummariesSettingsView: View {
    @State private var summaries = SummaryService.shared
    @State private var models = LocalModelManager.shared
    @State private var confirmDelete = false

    var body: some View {
        CardPage {
            CardSection {
                CardToggle(title: "Summarise contracts and letters", subtitle: "When you save one",
                           isOn: Binding(get: { summaries.autoSummarise }, set: { summaries.autoSummarise = $0 }))
            }
            CardSection(title: "Models on this phone") {
                CardRow(title: "English", subtitle: "Apple Intelligence · \(AppleSummarizer.availability.message)",
                        icon: (AppleSummarizer.availability == .available) ? "checkmark" : "xmark",
                        tint: (AppleSummarizer.availability == .available) ? Theme.Colors.verified : Theme.Colors.ink)
                chineseRow
            }
            if models.isInstalled {
                CardSection {
                    CardToggle(title: "Use it for Chinese", subtitle: "Apple's model is used when this is off",
                               isOn: Binding(get: { models.useForChinese }, set: { models.useForChinese = $0 }))
                    Button { confirmDelete = true } label: { CardRow(title: "Delete Chinese model", subtitle: String(format: "Frees %.1f GB", models.installedSizeGB), destructive: true) }
                        .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Summaries")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete the Chinese model? You can download it again later.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete model", role: .destructive) { models.delete() }
        }
    }

    @ViewBuilder private var chineseRow: some View {
        switch models.state {
        case .unavailable(let why):
            CardRow(title: "中文", subtitle: why, icon: "character.textbox")
        case .notInstalled:
            Button { Task { await models.download() } } label: {
                CardRow(title: "中文", subtitle: String(format: "Not installed · %.1f GB download", LocalModelManager.approxSizeGB), icon: "character.textbox", value: "Get")
            }
            .buttonStyle(.plain)
        case .downloading(let p):
            VStack(alignment: .leading, spacing: 8) {
                CardRow(title: "中文", subtitle: p < 0 ? "Downloading" : "Downloading · \(Int(p * 100))%", icon: "character.textbox")
                Group { if p < 0 { ProgressView() } else { ProgressView(value: p) } }
                    .padding(.horizontal, 16).padding(.bottom, 12)
            }
        case .installed, .ready, .loading:
            CardRow(title: "中文", subtitle: String(format: "Installed · %.1f GB", models.installedSizeGB), icon: "checkmark", tint: Theme.Colors.verified)
        case .failed(let e):
            Button { Task { await models.download() } } label: {
                CardRow(title: "中文", subtitle: e, icon: "exclamationmark.triangle", tint: Theme.Colors.danger, value: "Retry")
            }
            .buttonStyle(.plain)
        }
    }
}
