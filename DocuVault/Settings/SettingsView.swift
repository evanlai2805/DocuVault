import SwiftUI
import SwiftData
import DocuVaultCore
import DocuVaultOCR

struct SettingsView: View {
    @Query private var docs: [StoredDocument]
    @Environment(\.modelContext) private var context
    @State private var confirmWipe = false
    @State private var confirmResetKey = false
    @State private var models = LocalModelManager.shared
    @State private var summaries = SummaryService.shared
    @State private var confirmDeleteModel = false

    var body: some View {
        List {
            Section("OCR") {
                row("Languages", "English · 简体 · 繁體")
                row("Mode", "Accurate, on-device")
                row("Low-confidence mark", "below \(Int(OCRLine.lowConfidenceThreshold * 100))%")
            }
            Section("Summaries") {
                Toggle("Auto-summarise contracts and letters", isOn: Binding(get: { summaries.autoSummarise }, set: { summaries.autoSummarise = $0 }))
                row("English style", "STE: short sentences, active voice")
                row("Language", "Follows the document; mixed → asks")
                row("Apple model", AppleSummarizer.availability.message)
            }
            Section {
                Toggle("Use Qwen for Chinese", isOn: Binding(get: { models.useForChinese }, set: { models.useForChinese = $0 }))
                switch models.state {
                case .unavailable(let why): row("Status", why)
                case .notInstalled:
                    Button { Task { await models.download() } } label: {
                        HStack { Text("Download Chinese model"); Spacer(); Text(String(format: "%.1f GB", LocalModelManager.approxSizeGB)).foregroundStyle(Theme.Colors.ink2) }
                    }
                case .downloading(let p):
                    VStack(alignment: .leading, spacing: 6) {
                        Text(p < 0 ? "Downloading ~\(String(format: "%.1f", LocalModelManager.approxSizeGB)) GB… keep the app open" : "Downloading… \(Int(p * 100))%")
                        if p < 0 { ProgressView() } else { ProgressView(value: p) }
                    }
                case .installed, .ready:
                    row("Status", models.state == .ready ? "Loaded" : String(format: "Installed · %.1f GB", models.installedSizeGB))
                    Button(role: .destructive) { confirmDeleteModel = true } label: { Text("Delete Chinese model") }
                case .loading: row("Status", "Loading into memory…")
                case .failed(let e):
                    Text(e).font(.footnote).foregroundStyle(Theme.Colors.danger)
                    Button { Task { await models.download() } } label: { Text("Retry") }
                }
            } header: { Text("Chinese model (Qwen3 4B via MLX)") } footer: {
                Text("One-time download from Hugging Face. Runs fully on this phone after that. Apple's model is used whenever Qwen is off, missing, or fails.")
            }
            Section("Privacy") {
                row("Cloud sends", "0 — none configured")
                row("Storage", "App Group, Data Protection: Complete")
            }
            Section("Vault") {
                row("Client retention", "\(RetentionPolicy.clientDefaultDays) days, warn \(RetentionPolicy.warnDaysBefore) before")
                row("Auto-lock", "\(Int(VaultSession.autoLockSeconds)) s in background")
                NavigationLink { ExportView() } label: { Text("Export") }
                Button(role: .destructive) { confirmResetKey = true } label: { Text("Reset vault key") }
            }
            Section {
                Button(role: .destructive) { confirmWipe = true } label: { Text("Delete all documents (\(docs.count))") }
            }
            Section("About") {
                row("Version", "0.6.0 · Phase 6")
                row("Bundle", "com.evanlai.docuvault")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.canvas)
        .navigationTitle("Settings")
        .confirmationDialog("Delete the Chinese model? You can download it again later.", isPresented: $confirmDeleteModel, titleVisibility: .visible) {
            Button("Delete model", role: .destructive) { models.delete() }
        }
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

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k); Spacer(); Text(v).foregroundStyle(Theme.Colors.ink2).multilineTextAlignment(.trailing) }
    }
}
