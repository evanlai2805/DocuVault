import SwiftUI
import SwiftData
import DocuVaultCore
import DocuVaultOCR

/// Pages on top, selectable text below. Tap a page thumbnail to switch. Low-confidence lines are underlined amber.
struct DocumentDetailView: View {
    @Bindable var doc: StoredDocument
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var pageIndex = 0
    @State private var showImage = true
    @State private var confirmDelete = false

    private var pages: [StoredPage] { doc.orderedPages }
    private var page: StoredPage? { pages.indices.contains(pageIndex) ? pages[pageIndex] : nil }
    private var ocr: OCRPage? {
        guard let data = page?.ocrJSON else { return nil }
        return try? JSONDecoder().decode(OCRPage.self, from: data)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let page, let cg = PageStore.load(page.imageFileName) {
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

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Text").font(.system(size: 14)).textCase(.uppercase).tracking(0.5).foregroundStyle(Theme.Colors.ink2)
                        Spacer()
                        if let page {
                            StatusPill(text: page.ocrJSON == nil ? "PDF text" : "OCR \(Int(page.meanConfidence * 100))%",
                                       tone: page.ocrJSON == nil ? .info : (page.meanConfidence >= OCRLine.lowConfidenceThreshold ? .verified : .unverified))
                        }
                        Button { UIPasteboard.general.string = page?.text ?? "" } label: {
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
                Menu {
                    Button { showImage.toggle() } label: { Label(showImage ? "Hide image" : "Show image", systemImage: "photo") }
                    ShareLink(item: doc.fullText) { Label("Share text", systemImage: "square.and.arrow.up") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete document", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .confirmationDialog("Delete this document?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                for p in doc.pages { PageStore.delete(p.imageFileName) }
                context.delete(doc)
                try? context.save()
                dismiss()
            }
        }
    }

    /// Selectable text. Low-confidence lines get an amber underline via AttributedString.
    private var textBody: some View {
        let attributed: AttributedString = {
            guard let ocr else { return AttributedString(page?.text ?? "") }
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
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metaCard: some View {
        VStack(spacing: 0) {
            metaRow("Type", doc.type.displayName)
            Divider().padding(.leading, 16)
            metaRow("Language", doc.language == "en" ? "English" : (doc.language == "mixed" ? "Mixed" : "中文"))
            Divider().padding(.leading, 16)
            metaRow("Source", doc.source.displayName)
            Divider().padding(.leading, 16)
            metaRow("Captured", doc.capturedAt.formatted(date: .abbreviated, time: .shortened))
        }
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func metaRow(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(Theme.Colors.ink2); Spacer(); Text(v) }
            .font(.system(size: 17)).padding(16)
    }
}
