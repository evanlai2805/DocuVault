import SwiftUI
import SwiftData
import DocuVaultCore
import DocuVaultOCR

/// Last step of capture: OCR summary card, title, language, type, then save.
struct SaveDocumentView: View {
    let onDone: () -> Void
    @Environment(CaptureSession.self) private var capture
    @Environment(\.modelContext) private var context
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
                    CardHeader(title: "On-device OCR", subtitle: "en · zh-Hans · zh-Hant")
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
                    if capture.isSensitive || type.isSensitiveByDefault {
                        Divider().padding(.leading, 16)
                        HStack {
                            Text("Sensitive").font(.system(size: 17))
                            Spacer()
                            StatusPill(text: "Vault — Phase 4", tone: .info)
                        }
                        .padding(16)
                    }
                }
                .background(Theme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                if let ex = capture.extraction, !ex.fields.isEmpty {
                    HStack {
                        Text("\(ex.fields.count - ex.missingCount) of \(ex.fields.count) fields filled").font(.system(size: 16))
                        Spacer()
                        StatusPill(text: ex.checksTotal == 0 ? "no checks" : "\(ex.checksPassed)/\(ex.checksTotal) checks",
                                   tone: ex.checksTotal == 0 ? .neutral : (ex.allChecksPassed ? .verified : .missing))
                    }
                    .padding(16).background(Theme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                if capture.isSensitive {
                    HintBanner(badge: "SENSITIVE", title: "Looks like an ID or card",
                               detail: "It is saved in the Library for now. Phase 4 moves it into the Face ID vault automatically.")
                }

                if let error { Text(error).foregroundStyle(Theme.Colors.danger).font(.footnote) }
            }
            .padding(16)
        }
        .background(Theme.Colors.canvas)
        .navigationTitle("Save")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(saving ? "Saving…" : "Save") { Task { await save() } }
                    .fontWeight(.semibold)
                    .disabled(saving || title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            if title.isEmpty { title = capture.guessedTitle }
            language = capture.detectedLanguage
            type = capture.chosenType
        }
    }

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
            var storedPages: [StoredPage] = []
            let encoder = JSONEncoder()
            for (i, p) in capture.pages.enumerated() {
                let fileName = try PageStore.save(p.processed())
                var json: Data? = nil
                if case .done(let ocr) = p.ocr { json = try? encoder.encode(ocr) }
                storedPages.append(StoredPage(index: i, imageFileName: fileName, ocrJSON: json,
                                              text: p.text, meanConfidence: p.meanConfidence))
            }
            let storedFields = (capture.extraction?.fields ?? []).enumerated().map { StoredField(order: $0.offset, field: $0.element) }
            let doc = StoredDocument(title: title.trimmingCharacters(in: .whitespaces), type: type, language: language,
                                     sensitive: capture.isSensitive || type.isSensitiveByDefault,
                                     source: capture.source, fullText: capture.fullText, pages: storedPages,
                                     fields: storedFields,
                                     checksPassed: capture.extraction?.checksPassed ?? 0,
                                     checksTotal: capture.extraction?.checksTotal ?? 0)
            context.insert(doc)
            try context.save()
            capture.reset()
            onDone()
        } catch {
            self.error = "Save failed: \(error.localizedDescription)"
        }
    }
}
