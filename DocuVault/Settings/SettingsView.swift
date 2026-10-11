import SwiftUI
import SwiftData
import DocuVaultCore
import DocuVaultOCR

struct SettingsView: View {
    @Query private var docs: [StoredDocument]
    @Environment(\.modelContext) private var context
    @State private var confirmWipe = false

    var body: some View {
        List {
            Section("OCR") {
                row("Languages", "English · 简体 · 繁體")
                row("Mode", "Accurate, on-device")
                row("Low-confidence mark", "below \(Int(OCRLine.lowConfidenceThreshold * 100))%")
            }
            Section("Privacy") {
                row("Cloud sends", "0 — none configured")
                row("Storage", "App Group, Data Protection: Complete")
            }
            Section("Vault (Phase 4)") {
                row("Client retention", "\(RetentionPolicy.clientDefaultDays) days, warn \(RetentionPolicy.warnDaysBefore) before")
            }
            Section {
                Button(role: .destructive) { confirmWipe = true } label: { Text("Delete all documents (\(docs.count))") }
            }
            Section("About") {
                row("Version", "0.2.0 · Phase 2")
                row("Bundle", "com.evanlai.docuvault")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.canvas)
        .navigationTitle("Settings")
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
