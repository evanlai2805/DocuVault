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
    @State private var toast: String?
    @State private var largeType: LargeTypeView.Item?
    @State private var panRevealed = false
    @State private var showScan = false

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
                if doc.sensitive && vault.isUnlocked { vaultHeader }
                if retentionDaysLeft != nil { retentionBanner }
                if !doc.sensitive, let page, let cg = PageStore.load(page.imageFileName, vaultKey: vault.key) {
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

                if !doc.sensitive && pages.count > 1 {
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

                if !unverified.isEmpty {
                    verificationBanner
                }

                if SummarySpec.supportsSummary(doc.type), let full = vault.revealText(doc), !full.isEmpty {
                    SummaryCard(doc: doc, text: full)
                }

                if !doc.fields.isEmpty {
                    fieldsCard(doc.orderedFields.filter { $0.section == .main }, title: "Fields")
                    let secondary = doc.orderedFields.filter { $0.section == .secondary }
                    if !secondary.isEmpty { fieldsCard(secondary, title: "Secondary") }
                }

                if doc.sensitive && vault.isUnlocked && !pages.isEmpty { scanRow }

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
        .navigationTitle(doc.sensitive && vault.isUnlocked ? "" : doc.title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            if let toast {
                Label(toast, systemImage: "checkmark")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Theme.Colors.graphite).clipShape(Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .fullScreenCover(item: $largeType) { LargeTypeView(item: $0) }
        .fullScreenCover(isPresented: $showScan) { scanViewer }
        .onChange(of: vault.isUnlocked) { _, open in if !open { panRevealed = false; showScan = false } }
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
                RetentionManager.trash(doc, context: context)
                dismiss()
            }
        } message: {
            Text(doc.sensitive ? "Vault documents are deleted for good." : "It stays in Recently deleted for \(RetentionManager.recentlyDeletedDays) days.")
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
                Button { copy(f) } label: { fieldRow(f) }
                    .buttonStyle(.plain)
                    .contextMenu { fieldMenu(f) }
                if f.id != fields.last?.id { Divider().padding(.leading, 16) }
            }
        }
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: Fields, the 1Password way (checkpoint 16)

    /// Label above value, so long values get the full width. A card number stays masked until Reveal (Q6).
    private func fieldRow(_ f: StoredField) -> some View {
        let e = shown(f)
        let masked = f.key == "pan" && !panRevealed && !e.value.isEmpty && vault.reveal(f) != nil
        let display = masked ? "•••• •••• •••• " + String(e.value.filter(\.isNumber).suffix(4))
                             : (e.value.isEmpty ? "—" : CopyVariants.shown(fieldKey: f.key, value: e.value, type: doc.type))
        let expiry = DocumentExpiry.keys.contains(f.key) ? DocumentExpiry.phrase(expiryStatus) : nil
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(f.labelEN)
                    if let zh = f.labelZH { Text(zh) }
                }
                .font(.system(size: 13)).foregroundStyle(Theme.Colors.accent)
                Text(display)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(expiry != nil || e.check == .missing ? Theme.Colors.danger : Theme.Colors.ink)
                    .lineLimit(3).minimumScaleFactor(0.8)
                if let expiry { Text(expiry).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.Colors.danger) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if f.key == "pan", vault.reveal(f) != nil {
                Button(panRevealed ? "Hide" : "Reveal") { panRevealed.toggle() }
                    .font(.system(size: 15, weight: .semibold)).buttonStyle(.borderless)
            }
            FieldCheckTag(field: e, needsVerification: needsVerification(f))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    /// Hold: Copy, the same wordings the keyboard's hold menu inserts, Large type, Edit.
    @ViewBuilder private func fieldMenu(_ f: StoredField) -> some View {
        if let v = vault.reveal(f), !v.isEmpty {
            Button { copy(f) } label: { Label("Copy", systemImage: "doc.on.doc") }
            ForEach(CopyVariants.options(fieldKey: f.key, value: v, type: doc.type, fields: revealedFields)) { o in
                Button("Copy as \(o.text)") { copyText(o.text, label: f.labelEN) }
            }
            Divider()
            Button { largeType = .init(label: f.labelEN, value: CopyVariants.shown(fieldKey: f.key, value: v, type: doc.type)) } label: {
                Label("Large type", systemImage: "textformat.size")
            }
        }
        Button { beginEdit(f) } label: { Label("Edit", systemImage: "pencil") }
    }

    /// A tap copies what the row shows (Q7). Vault copies stay on this phone and clear after 60 s.
    private func copy(_ f: StoredField) {
        Task {
            if doc.sensitive && !vault.isUnlocked { await vault.unlock(reason: "Copy from this document") }
            guard let v = vault.reveal(f), !v.isEmpty else { return }
            copyText(CopyVariants.shown(fieldKey: f.key, value: v, type: doc.type), label: f.labelEN)
        }
    }

    private func copyText(_ text: String, label: String) {
        Clipboard.copy(text, sensitive: doc.sensitive)
        let line = doc.sensitive ? "Copied \(label) · Clears in 60 s" : "Copied \(label)"
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { toast = line }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.easeOut(duration: 0.2)) { if toast == line { toast = nil } }
        }
    }

    private var revealedFields: [String: String] {
        Dictionary(doc.fields.map { ($0.key, vault.reveal($0) ?? "") }, uniquingKeysWith: { a, _ in a })
    }

    private var expiryStatus: DocumentExpiry.Status { DocumentExpiry.status(type: doc.type, fields: revealedFields) }

    // MARK: Vault item header and scan (checkpoint 16)

    /// Icon tile coloured by state: green when every check passes, red when one failed, graphite when
    /// there is nothing to check. Then title, owner and the favourite star.
    private var vaultHeader: some View {
        let style: Theme.CardStyle = doc.checksTotal == 0 ? .graphite : (doc.allChecksPassed ? .green : .red)
        let checks = doc.checksTotal == 0 ? nil : "\(doc.checksPassed)/\(doc.checksTotal) checks"
        return HStack(spacing: 14) {
            Image(systemName: VaultDocRow.icon(doc.type)).font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 60, height: 60).background(style.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(doc.title).font(.system(size: 22, weight: .bold)).lineLimit(2).minimumScaleFactor(0.8)
                Text([doc.person?.name, doc.person?.kind.displayName, checks].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 15)).foregroundStyle(Theme.Colors.ink2)
            }
            Spacer(minLength: 0)
            Button { doc.favourite.toggle(); try? context.save() } label: {
                Image(systemName: doc.favourite ? "star.fill" : "star").font(.system(size: 22))
                    .foregroundStyle(doc.favourite ? Theme.Colors.accent : Theme.Colors.ink2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(doc.favourite ? "Remove from favourites" : "Add to favourites")
        }
        .padding(.horizontal, 4)
    }

    private var scanRow: some View {
        Button { showScan = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "doc.viewfinder").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.Colors.ink)
                    .frame(width: 44, height: 44).background(Theme.Colors.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(pages.count == 1 ? "1 page" : "\(pages.count) pages").font(.rowTitle).foregroundStyle(Theme.Colors.ink)
                    Text("Opens full screen, pinch to zoom").font(.rowSubtitle).foregroundStyle(Theme.Colors.ink2)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.Colors.ink2)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Sealed pages are decrypted into memory only while this viewer is open.
    private var scanViewer: some View {
        NavigationStack {
            TabView {
                ForEach(pages) { p in
                    if let cg = PageStore.load(p.imageFileName, vaultKey: vault.key) { ZoomableImage(image: cg) }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: pages.count > 1 ? .always : .never))
            .background(Color.black)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showScan = false } } }
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    // MARK: Retention (moved here from the Vault home's card, checkpoint 16)

    private var retentionDaysLeft: Int? {
        if case .warning(let left) = Retention.status(expiresAt: doc.expiresAt) { return left }
        return nil
    }

    private var retentionBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "clock.badge.exclamationmark").font(.system(size: 15, weight: .bold))
                Text("Deletes in \(retentionDaysLeft ?? 0) d").font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(Theme.Colors.danger)
            HStack(spacing: 8) {
                ForEach(Retention.Action.allCases, id: \.self) { a in
                    Button(a.rawValue) {
                        let deleting = a == .deleteNow
                        RetentionManager.apply(a, to: doc, context: context)
                        if deleting { dismiss() }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(a == .deleteNow ? Theme.Colors.danger : Theme.Colors.ink)
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .background(Theme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.danger.opacity(0.07))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.Colors.danger.opacity(0.25)))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: Verification (checkpoint 15)

    private func needsVerification(_ f: StoredField) -> Bool {
        FieldEdit.needsVerification(check: f.check, key: f.key, type: doc.type, documentAllPass: doc.allChecksPassed)
    }

    private var unverified: [StoredField] { doc.orderedFields.filter(needsVerification) }

    /// One line naming the fields, then Edit and Verified. Nothing about how the scan may have misread.
    private var verificationBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 14, weight: .bold))
                Text(FieldEdit.verificationLine(labels: unverified.map(\.labelEN))).font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(Theme.Colors.danger)
            HStack(spacing: 8) {
                Button { if let f = unverified.first { beginEdit(f) } } label: {
                    Text("Edit").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.Colors.ink)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(Theme.Colors.surface)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.Colors.danger.opacity(0.3)))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.pressScale)
                Button { Task { await verifyAll() } } label: {
                    Text("Verified").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(Theme.Colors.verified)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.pressScale)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.danger.opacity(0.07))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.Colors.danger.opacity(0.25)))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// "Verified": the user compared every flagged value with the document. Stored per field and never
    /// raised again; only a later edit that fails its checksum flags it once more.
    private func verifyAll() async {
        if doc.sensitive && !vault.isUnlocked { await vault.unlock(reason: "Verify this document") }
        guard !doc.sensitive || vault.isUnlocked else { return }
        for f in unverified {
            let old = f.check
            f.checkRaw = FieldCheck.userVerified.rawValue
            doc.checksPassed = FieldEdit.adjustedPassed(passed: doc.checksPassed, total: doc.checksTotal,
                                                        key: f.key, type: doc.type, old: old, new: .userVerified)
        }
        do { try context.save() } catch { context.rollback(); editError = "Could not save. Nothing was changed." }
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
