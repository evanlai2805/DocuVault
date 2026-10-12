import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import DocuVaultOCR

/// The Scan tab: import sheet, then pages editor once there are pages.
struct ScanHomeView: View {
    let onDone: () -> Void
    @Environment(CaptureSession.self) private var capture
    @State private var showCamera = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showFiles = false
    @State private var errorMessage: String?
    @State private var clipboardHasImage = UIPasteboard.general.hasImages

    var body: some View {
        Group {
            if capture.hasPages {
                PagesEditorView(onDone: onDone)
            } else {
                importList
            }
        }
        .navigationTitle("Add Document")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !capture.hasPages {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onDone() }
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            DocumentCameraView(
                onFinish: { images in
                    capture.add(images, source: .camera)
                    showCamera = false
                },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPhotos(items); photoItems = [] }
        }
        .fileImporter(isPresented: $showFiles,
                      allowedContentTypes: [.image, .pdf],
                      allowsMultipleSelection: true) { result in
            Task { await importFiles(result) }
        }
        .alert("Import failed", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            clipboardHasImage = UIPasteboard.general.hasImages
        }
        .onAppear { clipboardHasImage = UIPasteboard.general.hasImages }
    }

    private var importList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Button { showCamera = true } label: {
                    IconRow(title: "Scan with camera", subtitle: "Multi-page · auto edge detection", systemImage: "camera.fill", tint: Theme.Colors.accent)
                }
                .disabled(!DocumentCameraView.isSupported)

                PhotosPicker(selection: $photoItems, maxSelectionCount: 30, matching: .images) {
                    IconRow(title: "Choose from Photos", subtitle: "Select one or many", systemImage: "photo.on.rectangle.angled")
                }

                Button { showFiles = true } label: {
                    IconRow(title: "Pick from Files", subtitle: "JPG · PNG · HEIC · PDF", systemImage: "folder.fill")
                }

                if clipboardHasImage {
                    Button { importClipboard() } label: {
                        IconRow(title: "Paste from clipboard", subtitle: "Image found on clipboard", systemImage: "doc.on.clipboard.fill")
                    }
                }

                HintBanner(badge: "ON-DEVICE", title: "Nothing is uploaded",
                           detail: "OCR runs on this iPhone in English and Chinese. Sensitive documents never leave it.")
                    .padding(.top, 18)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Theme.Colors.canvas)
    }

    // MARK: - Importers

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        var images: [CGImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let cg = ImageNormalizer.load(data: data) {
                images.append(cg)
            }
        }
        if images.isEmpty { errorMessage = "No readable images were selected." }
        capture.addSeparate(images, source: .photos)   // one document per photo
    }

    private func importFiles(_ result: Result<[URL], Error>) async {
        switch result {
        case .failure(let e):
            errorMessage = e.localizedDescription
        case .success(let urls):
            var images: [CGImage] = []
            for url in urls {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                if url.pathExtension.lowercased() == "pdf" {
                    do {
                        let pages = try PDFImporter.importPDF(url: url)
                        capture.addPDF(pages)
                    } catch {
                        errorMessage = "Could not read \(url.lastPathComponent)."
                    }
                } else if let cg = ImageNormalizer.load(url: url) {
                    images.append(cg)
                }
            }
            if !images.isEmpty { capture.addSeparate(images, source: .files) }   // one document per image file
        }
    }

    private func importClipboard() {
        let pb = UIPasteboard.general
        var images: [CGImage] = []
        if let datas = pb.data(forPasteboardType: UTType.image.identifier) .map({ [$0] }) {
            images = datas.compactMap { ImageNormalizer.load(data: $0) }
        }
        if images.isEmpty, let uiImages = pb.images {
            images = uiImages.compactMap { $0.uprightCGImage() }
        }
        if images.isEmpty { errorMessage = "No image on the clipboard."; return }
        capture.add(images, source: .clipboard)
    }
}
