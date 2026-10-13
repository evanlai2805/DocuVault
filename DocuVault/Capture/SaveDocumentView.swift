import SwiftUI
import SwiftData
import CryptoKit
import DocuVaultCore
import DocuVaultOCR

/// Last step of capture: OCR summary card, title, language, type, then save.
struct SaveDocumentView: View {
    let onDone: () -> Void
    /// Batch: called instead of `onDone` when another document is waiting.
    var onNext: () -> Void = {}
    @Environment(CaptureSession.self) private var capture
    @Environment(VaultSession.self) private var vault
    @Environment(\.modelContext) private var context
    @Query(sort: \StoredPerson.createdAt) private var people: [StoredPerson]
    @State private var ownerID: UUID?
    @State private var showAddPerson = false
    @State private var title = ""
    @State private var type: DocumentType = .other
    @State private var language = "en"
    @State private var saving = false
    @State private var error: String?

    private var pagesDone: Int { capture.pages.filter { if case .done = $0.ocr { return true }; if case .embedded = $0.ocr { return true }; return false }.count }
    private var meanConfidence: Double {
        let ps = capture.pages.filter { $0.meanConfidence > 0 }
        guard !ps.isEmpty else { return 0 }
        return ps.map(\.meanConfidence).reduce(0, +) / Double(ps.count)
    }
    private var lowPages: [Int] {
        capture.pages.enumerated().compactMap { i, p in
            if case .done(let o) = p.ocr, o.meanConfidence < OCRLine.lowConfidenceThreshold { return i + 1 }
            return nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GradientCard(style: .graphite) {
                    CardHeader(title: "On-device OCR", subtitle: "English · 简体 · 繁體")
                    HStack(alignment: .top, spacing: 10) {
                        StatBlock(label: "Confidence", value: "\(Int(meanConfidence * 100))%",
                                  footnote: lowPages.isEmpty ? "All pages clear" : "Low: page \(lowPages.map(String.init).joined(separator: ", "))")
                        StatBlock(label: "Language", value: languageLabel(capture.detectedLanguage),
                                  footnote: "\(Int(TextRules.cjkRatio(capture.fullText) * 100))% CJK", small: true)
                    }
                    HStack(alignment: .top, spacing: 10) {
                        StatBlock(label: "Pages", value: "\(pagesDone)/\(capture.pages.count)", small: true)
                        StatBlock(label: "Lines", value: "\(capture.allTextLines.filter { !$0.isEmpty }.count)", small: true)
                    }
                    .padding(.top, 14)
                }

                VStack(spacing: 0) {
                    field("Title") { TextField("Title", text: $title).font(.system(size: 17, weight: .semibold)) }
                    Divider().padding(.leading, 16)
                    field("Type") {
                        Picker("Type", selection: $type) {
                            ForEach(DocumentType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden().tint(Theme.Colors.ink)
                    }
                    Divider().padding(.leading, 16)
                    field("Language") {
                        Picker("Language", selection: $language) {
                            Text("English").tag("en"); Text("中文").tag("zh-Hans"); Text("Mixed").tag("mixed")
                        }
                        .labelsHidden().tint(Theme.Colors.ink)
                    }
                    if isSensitive {
                        Divider().padding(.leading, 16)
                        field("Owner") {
                            Picker("Owner", selection: $ownerID) {
                                Text("Choose…").tag(Optional<UUID>.none)
                                ForEach(people) { p in Text(p.name).tag(Optional(p.id)) }
                            }
                            .labelsHidden().tint(Theme.Colors.ink).lineLimit(1).fixedSize()
                            if let p = people.first(where: { $0.id == ownerID }) {
                                Text(p.kind.displayName).font(.system(size: 15)).foregroundStyle(Theme.Colors.ink2).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Button { showAddPerson = true } label: { Image(systemName: "plus.circle.fill") }
                        }
                        Divider().padding(.leading, 16)
                        HStack {
                            Text("Vault").font(.system(size: 17))
                            Spacer()
                            StatusPill(text: vault.isUnlocked ? "Unlocked · Will seal" : "Face ID on save", tone: .info)
                        }
                        .padding(16)
                        if let p = people.first(where: { $0.id == ownerID }), let days = p.retentionDays {
                            Divider().padding(.leading, 16)
                            HStack { Text("Retention").font(.system(size: 17)); Spacer(); Text("Deletes after \(days) d").foregroundStyle(Theme.Colors.ink2) }.padding(16)
                        }
                    }
                }
                .background(Theme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                if let ex = capture.extraction, !ex.fields.isEmpty {
                    HStack {
                        Text("\(ex.fields.count - ex.missingCount) of \(ex.fields.count) fields filled").font(.system(size: 16))
                        Spacer()
                        StatusPill(text: ex.checksTotal == 0 ? "No checks" : "\(ex.checksPassed)/\(ex.checksTotal) checks",
                                   tone: ex.checksTotal == 0 ? .neutral : (ex.allChecksPassed ? .verified : .missing))
                    }
                    .padding(16).background(Theme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                if isSensitive {
                    HintBanner(badge: "VAULT", title: "Sealed on this device",
                               detail: "Fields, text and page images are encrypted with the vault key. Face ID opens them. Nothing is uploaded.")
                }

                if let error { Text(error).foregroundStyle(Theme.Colors.danger).font(.footnote) }
            }
            .padding(16)
        }
        .background(Theme.Colors.canvas)
        .navigationTitle(capture.isBatch ? "Save · \(capture.batchPosition) of \(capture.batchTotal)" : "Save")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(saving ? "Saving…" : (isSensitive ? "Save to Vault" : "Save")) { Task { await save() } }
                    .fontWeight(.semibold)
                    .disabled(saving || title.trimmingCharacters(in: .whitespaces).isEmpty || (isSensitive && ownerID == nil))
            }
        }
        .sheet(isPresented: $showAddPerson) { AddPersonSheet() }
        .onAppear {
            if title.isEmpty { title = capture.guessedTitle }
            language = capture.detectedLanguage
            type = capture.chosenType
        }
    }

    private var isSensitive: Bool { capture.isSensitive || type.isSensitiveByDefault }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack {
            Text(label).font(.system(size: 17)).foregroundStyle(Theme.Colors.ink2).frame(width: 90, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private func languageLabel(_ code: String) -> String {
        switch code { case "zh-Hans": return "中文"; case "mixed": return "Mixed"; default: return "EN" }
    }

    @MainActor
    private func save() async {
        saving = true
        defer { saving = false }
        do {
            var key: SymmetricKey? = nil
            if isSensitive {
                if !vault.isUnlocked { await vault.unlock(reason: "Seal this document in your vault") }
                guard let k = vault.key else { error = vault.lastError ?? "Face ID is required to save to the vault."; return }
                key = k
            }
            var storedPages: [StoredPage] = []
            let encoder = JSONEncoder()
            for (i, p) in capture.pages.enumerated() {
                let fileName = try PageStore.save(p.processed(), vaultKey: key)
                var json: Data? = nil
                if case .done(let ocr) = p.ocr, key == nil { json = try? encoder.encode(ocr) }   // boxes carry text; skip for sealed docs
                storedPages.append(StoredPage(index: i, imageFileName: fileName, ocrJSON: json,
                                              text: key == nil ? p.text : "", meanConfidence: p.meanConfidence))
            }
            var storedFields: [StoredField] = []
            for (i, f) in (capture.extraction?.fields ?? []).enumerated() {
                let sealed: Data? = try key.map { try VaultCrypto.seal(f.value, key: $0) }
                storedFields.append(StoredField(order: i, field: f, sealedValue: sealed))
            }
            let owner = people.first { $0.id == ownerID }
            let doc = StoredDocument(title: title.trimmingCharacters(in: .whitespaces), type: type, language: language,
                                     sensitive: isSensitive,
                                     source: capture.source, fullText: key == nil ? capture.fullText : "", pages: storedPages,
                                     fields: storedFields,
                                     checksPassed: capture.extraction?.checksPassed ?? 0,
                                     checksTotal: capture.extraction?.checksTotal ?? 0,
                                     person: owner,
                                     expiresAt: Retention.expiryDate(capturedAt: Date(), retentionDays: owner?.retentionDays),
                                     sealedText: try key.map { try VaultCrypto.seal(capture.fullText, key: $0) })
            context.insert(doc)
            try context.save()
            if ExportManager.shared.syncFolder { ExportManager.shared.exportAll(context: context, vaultKey: vault.key) }
            // Auto-summarise contracts and letters in the background (Evan: on). Mixed-language docs wait for a language pick.
            if SummaryService.shared.autoSummarise, SummarySpec.supportsSummary(type), key == nil {
                let text = capture.fullText
                let ctx = context
                Task { await SummaryService.shared.summarise(doc, text: text, context: ctx) }
            }
            if capture.advance() {
                onNext()
                Task { await capture.prepareCurrent() }
            } else {
                onDone()
            }
        } catch {
            self.error = "Save failed: \(error.localizedDescription)"
        }
    }
}
