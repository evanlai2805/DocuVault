import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import DocuVaultOCR

/// The Scan tab: import sheet, then pages editor once there are pages.
struct ScanHomeView: View {
    @Environment(CaptureSession.self) private var capture
    @State private var showCamera = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showFiles = false
    @State private var errorMessage: String?
    @State private var clipboardHasImage = UIPasteboard.general.hasImages

    var body: some View {
        Group {
            if capture.hasPages {
                PagesEditorView()
            } else {
                importList
            }
        }
        .navigationTitle("Scan")
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
        List {
            Section {
                Button { showCamera = true } label: {
                    row("Scan with camera", "camera.fill", "Multi-page, auto edge detection")
                }
                .disabled(!DocumentCameraView.isSupported)

                PhotosPicker(selection: $photoItems, maxSelectionCount: 30, matching: .images) {
                    row("Choose from Photos", "photo.on.rectangle", "Select one or many")
                }

                Button { showFiles = true } label: {
                    row("Pick from Files", "folder.fill", "JPG · PNG · HEIC · PDF")
                }

                if clipboardHasImage {
                    Button { importClipboard() } label: {
                        row("Paste from clipboard", "doc.on.clipboard.fill", "Image found on clipboard")
                    }
                }
            } header: {
                Text("Import")
            } footer: {
                Text("OCR runs on this device in English and Chinese. Nothing is uploaded.")
            }
        }
    }

    private func row(_ title: String, _ icon: String, _ subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title3).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary).fontWeight(.semibold)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
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
        capture.add(images, source: .photos)
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
            if !images.isEmpty { capture.add(images, source: .files) }
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
