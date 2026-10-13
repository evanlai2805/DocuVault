import SwiftUI
import SwiftData
import CryptoKit
import DocuVaultCore
import DocuVaultOCR

/// Pages on top, selectable text below. Tap a page thumbnail to switch. Low-confidence lines are underlined amber.
struct DocumentDetailView: View {
    @Bindable var doc: StoredDocument
    @Environment(VaultSession.self) private var vault
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var pageIndex = 0
    @State private var showImage = true
    @State private var confirmDelete = false
    @State private var editing: StoredField?
    @State private var editScan: CGImage?
    @State private var editError: String?

    private var pages: [StoredPage] { doc.orderedPages }
    private var page: StoredPage? { pages.indices.contains(pageIndex) ? pages[pageIndex] : nil }
    private var ocr: OCRPage? {
        guard let data = page?.ocrJSON else { return nil }
        return try? JSONDecoder().decode(OCRPage.self, from: data)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if doc.sensitive && !vault.isUnlocked {
                    HintBanner(badge: "LOCKED", title: "Vault is locked", detail: "Open the Vault tab and pass Face ID to see this document.")
                }
                if let page, let cg = PageStore.load(page.imageFileName, vaultKey: vault.key) {
                    ZStack(alignment: .topLeading) {
                        Image(decorative: cg, scale: 1).resizable().scaledToFit()
                        if let ocr {
                            OCRBoxesOverlay(ocr: ocr, imageSize: CGSize(width: cg.width, height: cg.height))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .frame(maxHeight: showImage ? 420 : 0)
                    .clipped()
                }

                if pages.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(pages.enumerated()), id: \.element.id) { i, p in
                                Button { pageIndex = i } label: {
                                    Text("\(i + 1)").font(.chip)
                                        .frame(width: 44, height: 44)
                                        .foregroundStyle(i == pageIndex ? Theme.Colors.ink : Theme.Colors.ink2)
                                        .background(i == pageIndex ? Theme.Colors.surface : .clear)
                                        .overlay(Circle().stroke(i == pageIndex ? Theme.Colors.hairline : .clear))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if SummarySpec.supportsSummary(doc.type), let full = vault.revealText(doc), !full.isEmpty {
                    SummaryCard(doc: doc, text: full)
                }

                if !doc.fields.isEmpty {
                    fieldsCard(doc.orderedFields.filter { $0.section == .main }, title: "Fields")
                    let secondary = doc.orderedFields.filter { $0.section == .secondary }
                    if !secondary.isEmpty { fieldsCard(secondary, title: "Secondary") }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Text").font(.system(size: 14)).textCase(.uppercase).tracking(0.5).foregroundStyle(Theme.Colors.ink2)
                        Spacer()
                        if let page {
                            StatusPill(text: page.ocrJSON == nil ? "PDF text" : "OCR \(Int(page.meanConfidence * 100))%",
                                       tone: page.ocrJSON == nil ? .info : (page.meanConfidence >= OCRLine.lowConfidenceThreshold ? .verified : .unverified))
                        }
                        Button { Clipboard.copy(pageText, sensitive: doc.sensitive) } label: {
                            Image(systemName: "doc.on.doc").font(.system(size: 15, weight: .medium))
                        }
                    }
                    textBody
                }
                .padding(16)
                .background(Theme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                metaCard
            }
            .padding(16)
        }
        .background(Theme.Colors.canvas)
        .navigationTitle(doc.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let first = doc.orderedFields.first {
                    Button { beginEdit(first) } label: { Label("Edit", systemImage: "pencil") }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showImage.toggle() } label: { Label(showImage ? "Hide image" : "Show image", systemImage: "photo") }
                    ShareLink(item: vault.revealText(doc) ?? "") { Label("Share text", systemImage: "square.and.arrow.up") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete document", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(item: $editing) { f in
            FieldEditSheet(field: shown(f), hints: editHints(f), type: doc.type, scan: editScan) { newValue in
                Task { await saveEdit(f, newValue) }
            }
            .presentationDetents([.large])
        }
        .alert("Edit not saved", isPresented: Binding(get: { editError != nil }, set: { if !$0 { editError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(editError ?? "") }
        .confirmationDialog("Delete this document?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                for p in doc.pages { PageStore.delete(p.imageFileName) }
                context.delete(doc)
                try? context.save()
                dismiss()
            }
        }
    }

    /// Current page text; for sealed documents the whole text is one blob, so show it on page 1.
    private var pageText: String {
        if doc.sealedText != nil { return pageIndex == 0 ? (vault.revealText(doc) ?? "") : "" }
        return page?.text ?? ""
    }

    /// Selectable text. Low-confidence lines get an amber underline via AttributedString.
    private var textBody: some View {
        let attributed: AttributedString = {
            guard let ocr else { return AttributedString(pageText) }
            var out = AttributedString()
            for (i, line) in ocr.readingOrder.enumerated() {
                var a = AttributedString(line.text)
                if line.isLowConfidence {
                    a.underlineStyle = .single
                    a.underlineColor = UIColor(Theme.Colors.warning)
                }
                out += a
                if i < ocr.lines.count - 1 { out += AttributedString("\n") }
            }
            return out
        }()
        return Text(attributed)
            .font(.system(size: 17))
            .textSelection(.enabled)
            .writingToolsBehavior(.complete)   // Apple Writing Tools: Summarise, Key Points, Rewrite, Translate on selection
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fieldsCard(_ fields: [StoredField], title: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.system(size: 14)).textCase(.uppercase).tracking(0.5).foregroundStyle(Theme.Colors.ink2)
                Spacer()
                if title == "Fields" {
                    StatusPill(text: doc.checksTotal == 0 ? "No checks" : "\(doc.checksPassed)/\(doc.checksTotal) checks",
                               tone: doc.checksTotal == 0 ? .neutral : (doc.allChecksPassed ? .verified : .missing))
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)
            ForEach(fields) { f in
                Button { beginEdit(f) } label: { FieldRow(field: shown(f)) }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { Clipboard.copy(vault.reveal(f) ?? "", sensitive: doc.sensitive) } label: { Label("Copy", systemImage: "doc.on.doc") }
                        Button { beginEdit(f) } label: { Label("Edit", systemImage: "pencil") }
                    }
                if f.id != fields.last?.id { Divider().padding(.leading, 16) }
            }
        }
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func shown(_ f: StoredField) -> ExtractedField {
        var e = f.asExtracted
        e.value = vault.reveal(f) ?? "••••••"
        return e
    }

    // MARK: Edit (checkpoint 14 Q1)

    /// A vault document needs Face ID before its value can be shown in the sheet.
    private func beginEdit(_ f: StoredField) {
        Task {
            if doc.sensitive && !vault.isUnlocked { await vault.unlock(reason: "Edit this document") }
            guard !doc.sensitive || vault.isUnlocked else { return }
            editScan = page.flatMap { PageStore.load($0.imageFileName, vaultKey: vault.key) }
            editing = f
        }
    }

    private func editHints(_ f: StoredField) -> [String] {
        guard doc.type == .passport, ["passportNumber", "dateOfBirth", "expiry"].contains(f.key) else { return [] }
        return ["The MRZ check cannot re-run on one field. Saving marks it Edited: checked by you against the scan."]
    }

    /// Normalise, re-run the field's own checksum, re-seal for the vault, and move the document's
    /// pass count. A failed checksum still saves; the count drops and the card turns red.
    private func saveEdit(_ f: StoredField, _ raw: String) async {
        let value = FieldEdit.normalize(key: f.key, value: raw, type: doc.type)
        let old = f.check
        let new = FieldEdit.recheck(key: f.key, value: value, type: doc.type)
        var key: SymmetricKey?
        if doc.sensitive {
            if !vault.isUnlocked { await vault.unlock(reason: "Save your edit to the vault") }
            guard let k = vault.key else { editError = vault.lastError ?? "Face ID is required to save to the vault."; return }
            key = k
        }
        do {
            try write(value, to: f, key: key)
            f.checkRaw = new.rawValue
            doc.checksPassed = FieldEdit.adjustedPassed(passed: doc.checksPassed, total: doc.checksTotal,
                                                        key: f.key, type: doc.type, old: old, new: new)
            for (k, v) in FieldEdit.derived(key: f.key, value: value) {
                if let d = doc.fields.first(where: { $0.key == k }) { try write(v, to: d, key: key) }
            }
            try context.save()
            if ExportManager.shared.syncFolder { ExportManager.shared.exportAll(context: context, vaultKey: vault.key) }
        } catch {
            context.rollback()
            editError = "Could not save the edit. Nothing was changed."
        }
    }

    private func write(_ v: String, to f: StoredField, key: SymmetricKey?) throws {
        if let key {
            f.sealedValue = try VaultCrypto.seal(v, key: key)
            f.value = ""
        } else {
            f.value = v
        }
    }

    private var metaCard: some View {
        VStack(spacing: 0) {
            metaRow("Type", doc.type.displayName)
            Divider().padding(.leading, 16)
            metaRow("Language", doc.language == "en" ? "English" : (doc.language == "mixed" ? "Mixed" : "中文"))
            Divider().padding(.leading, 16)
            metaRow("Source", doc.source.displayName)
            Divider().padding(.leading, 16)
            metaRow("Captured", doc.capturedAt.dvDisplay(time: true))
        }
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func metaRow(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(Theme.Colors.ink2); Spacer(); Text(v) }
            .font(.system(size: 17)).padding(16)
    }
}
