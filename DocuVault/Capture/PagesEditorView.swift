import SwiftUI
import DocuVaultOCR

/// Review pages before OCR: rotate, enhance, delete, reorder. Then run OCR and watch progress.
struct PagesEditorView: View {
    let onDone: () -> Void
    @Environment(CaptureSession.self) private var capture
    @State private var selected: DraftPage.ID?
    @State private var goToSave = false

    var body: some View {
        VStack(spacing: 0) {
            if let page = selectedPage {
                PagePreview(page: page)
                    .frame(maxHeight: .infinity)
                controls(for: page)
            }
            thumbnailStrip
        }
        .background(Theme.Colors.canvas)
        .navigationTitle(capture.isBatch
                         ? "Document \(capture.batchPosition) of \(capture.batchTotal) · \(capture.pages.count) page\(capture.pages.count == 1 ? "" : "s")"
                         : "\(capture.pages.count) page\(capture.pages.count == 1 ? "" : "s")")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(capture.isBatch ? "Discard all" : "Discard", role: .destructive) { capture.reset(); onDone() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if capture.ocrComplete && !capture.isRunningOCR {
                    Button("Review") { capture.classifyAndExtract(); goToSave = true }.fontWeight(.semibold)
                } else {
                    Button(capture.isRunningOCR ? "Reading \(capture.ocrProgress.done)/\(capture.ocrProgress.total)…" : (capture.isBatch ? "Run OCR on all" : "Run OCR")) {
                        Task { await capture.runOCR() }
                    }
                    .disabled(capture.isRunningOCR)
                    .fontWeight(.semibold)
                }
            }
        }
        .navigationDestination(isPresented: $goToSave) { ReviewView(onDone: onDone) }
        .onAppear { if selected == nil { selected = capture.pages.first?.id } }
        .onChange(of: capture.pages.map(\.id)) { _, ids in
            if let s = selected, !ids.contains(s) { selected = ids.first }
            if selected == nil { selected = ids.first }
        }
    }

    private var selectedPage: DraftPage? { capture.pages.first { $0.id == selected } }

    private func controls(for page: DraftPage) -> some View {
        VStack(spacing: 10) {
            HStack {
                Picker("Enhance", selection: Binding(
                    get: { page.enhance },
                    set: { capture.setEnhance(page.id, $0) })) {
                    ForEach(DraftPage.Enhance.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(page.embeddedText != nil)
            }
            HStack(spacing: 24) {
                Button { capture.rotate(page.id) } label: { Label("Rotate", systemImage: "rotate.right") }
                Button(role: .destructive) { capture.remove(page.id) } label: { Label("Delete", systemImage: "trash") }
                if capture.isBatch || capture.pages.count > 1 {
                    Menu {
                        if !capture.queue.isEmpty {
                            Button { capture.mergeNextIntoCurrent() } label: { Label("Merge next document into this one", systemImage: "arrow.turn.down.left") }
                        }
                        if capture.pages.count > 1 {
                            Button { capture.splitOff(page.id) } label: { Label("Split this page into its own document", systemImage: "arrow.turn.up.right") }
                        }
                    } label: { Label("Batch", systemImage: "square.stack") }
                }
                Spacer()
                OCRStatusPill(state: page.ocr)
            }
            .font(.subheadline)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var thumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(capture.pages.enumerated()), id: \.element.id) { idx, page in
                    VStack(spacing: 4) {
                        Image(decorative: page.processed(), scale: 1)
                            .resizable().scaledToFit()
                            .frame(width: 56, height: 74)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .stroke(page.id == selected ? Color.accentColor : Color(.separator),
                                        lineWidth: page.id == selected ? 2.5 : 1))
                        Text("\(idx + 1)").font(.caption2).foregroundStyle(.secondary)
                    }
                    .onTapGesture { selected = page.id }
                    .draggable(page.id.uuidString)
                    .dropDestination(for: String.self) { items, _ in
                        guard let s = items.first, let from = capture.pages.firstIndex(where: { $0.id.uuidString == s }),
                              let to = capture.pages.firstIndex(where: { $0.id == page.id }) else { return false }
                        capture.move(from: IndexSet(integer: from), to: to > from ? to + 1 : to)
                        return true
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }
}

struct PagePreview: View {
    let page: DraftPage
    var body: some View {
        GeometryReader { geo in
            let img = page.processed()
            ZStack(alignment: .topLeading) {
                Image(decorative: img, scale: 1)
                    .resizable().scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
                if case .done(let ocr) = page.ocr {
                    OCRBoxesOverlay(ocr: ocr, imageSize: CGSize(width: img.width, height: img.height))
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .padding(8)
    }
}

/// Draws Vision boxes over the fitted image. Amber for low confidence.
struct OCRBoxesOverlay: View {
    let ocr: OCRPage
    let imageSize: CGSize
    var body: some View {
        GeometryReader { geo in
            let fit = fittedRect(in: geo.size)
            ForEach(ocr.lines) { line in
                let r = line.box
                Rectangle()
                    .stroke(line.isLowConfidence ? Color.orange : Color.green.opacity(0.7), lineWidth: 1.2)
                    .frame(width: r.width * fit.width, height: r.height * fit.height)
                    .position(x: fit.minX + (r.midX) * fit.width,
                              y: fit.minY + (1 - r.midY) * fit.height)
            }
        }
    }
    private func fittedRect(in container: CGSize) -> CGRect {
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let w = imageSize.width * scale, h = imageSize.height * scale
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }
}

struct OCRStatusPill: View {
    let state: DraftPage.OCRState
    var body: some View {
        switch state {
        case .queued: pill("Queued", .gray)
        case .running: HStack(spacing: 6) { ProgressView().controlSize(.mini); pill("Reading…", .orange) }
        case .done(let p): pill("OCR \(Int(p.meanConfidence * 100))%", p.meanConfidence >= 0.8 ? .green : .orange)
        case .embedded: pill("PDF text", .blue)
        case .failed: pill("Failed", .red)
        }
    }
    private func pill(_ t: String, _ c: Color) -> some View {
        Text(t).font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(c.opacity(0.15)).foregroundStyle(c)
            .clipShape(Capsule())
    }
}
