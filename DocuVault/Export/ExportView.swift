import SwiftUI
import SwiftData
import DocuVaultCore

/// Export (checkpoint 17): a navy card says what the plain-text copy holds, then the two switches and
/// Export now. The in-app copy is always written; folder sync is optional.
struct ExportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(VaultSession.self) private var vault
    @Query(filter: #Predicate<StoredDocument> { $0.deletedAt == nil }) private var docs: [StoredDocument]
    @State private var showPicker = false
    @State private var exporting = false

    var body: some View {
        @Bindable var ex = ExportManager.shared
        CardPage {
            GradientCard(style: .navy) {
                CardHeader(title: "Plain-text copy", subtitle: "Markdown files · expenses.csv")
                HStack(alignment: .top, spacing: 10) {
                    StatBlock(label: "Documents", value: "\(docs.count)", small: true)
                    StatBlock(label: "Receipts", value: "\(docs.filter { $0.type == .receipt }.count)", small: true)
                    StatBlock(label: "Last written", value: ex.lastExport.map { $0.formatted(date: .omitted, time: .shortened) } ?? "Never", small: true)
                }
            }

            CardSection(note: ex.syncFolder ? "A DocuVault folder inside it is rewritten on every save. Other files there are never touched." : nil) {
                CardToggle(title: "Also write to a folder", subtitle: ex.syncFolder ? (ex.folderName ?? "Choose a folder") : "Files, iCloud Drive or a drive", isOn: $ex.syncFolder)
                if ex.syncFolder {
                    Button { showPicker = true } label: { CardRow(title: "Folder", value: ex.folderName ?? "Choose", chevron: true) }
                        .buttonStyle(.plain)
                    CardToggle(title: "Include page images", isOn: $ex.includeImages)
                }
            }

            CardSection(note: vault.isUnlocked ? nil : "The vault is locked, so sealed documents will be skipped.") {
                Button { Task { await run() } } label: {
                    Text(exporting ? "Exporting" : "Export now")
                        .font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.Colors.accent)
                        .frame(maxWidth: .infinity).padding(.vertical, 14).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(exporting)
            }
            if let e = ex.lastError {
                Text(e).font(.system(size: 14)).foregroundStyle(Theme.Colors.danger).padding(.horizontal, 4)
            }
        }
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { ExportManager.shared.setFolder(url) }
        }
    }

    private func run() async {
        exporting = true
        ExportManager.shared.exportAll(context: context, vaultKey: vault.key)
        exporting = false
    }
}
