import SwiftUI
import SwiftData
import DocuVaultCore

/// Export settings and "Export now". In-app mirror always; folder sync optional.
struct ExportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(VaultSession.self) private var vault
    @State private var showPicker = false
    @State private var exporting = false
    private var export: ExportManager { ExportManager.shared }

    var body: some View {
        @Bindable var ex = ExportManager.shared
        List {
            Section {
                HStack {
                    Label("In app", systemImage: "iphone")
                    Spacer()
                    Text("Always · encrypted at rest").foregroundStyle(Theme.Colors.ink2)
                }
                Toggle(isOn: $ex.syncFolder) { Label("Also write to a folder", systemImage: "folder") }
                if ex.syncFolder {
                    Button { showPicker = true } label: {
                        HStack { Text("Folder"); Spacer(); Text(ex.folderName ?? "Choose…").foregroundStyle(Theme.Colors.ink2) }
                    }
                    Toggle(isOn: $ex.includeImages) { Text("Include page images") }
                }
            } header: { Text("Destination") } footer: {
                Text("Plain text. A DocuVault/ folder is created inside the folder you pick and rewritten on every save. Other files there are never touched.")
            }
            Section("What is written") {
                row("vault/<person>/<type>-<title>.md", "one file per document")
                row("vault/index.md", "everyone · type · expiry · checks · deletions")
                row("expenses.csv", "one row per receipt")
                row("images/", ex.includeImages ? "on" : "off")
            }
            Section {
                Button { Task { await run() } } label: {
                    HStack { Text(exporting ? "Exporting…" : "Export now"); Spacer(); if let d = ex.lastExport { Text(d.formatted(date: .omitted, time: .shortened)).foregroundStyle(Theme.Colors.ink2) } }
                }
                .disabled(exporting)
                if let e = ex.lastError { Text(e).foregroundStyle(Theme.Colors.danger).font(.footnote) }
                if !vault.isUnlocked { Text("Vault is locked: sealed documents will be skipped.").font(.footnote).foregroundStyle(Theme.Colors.warning) }
            }
        }
        .scrollContentBackground(.hidden).background(Theme.Colors.canvas)
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { ExportManager.shared.setFolder(url) }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(k).font(.system(size: 15, design: .monospaced)); Text(v).font(.footnote).foregroundStyle(Theme.Colors.ink2) }
    }

    private func run() async {
        exporting = true
        ExportManager.shared.exportAll(context: context, vaultKey: vault.key)
        exporting = false
    }
}
