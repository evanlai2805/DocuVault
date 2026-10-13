import Foundation
import SwiftData
import CryptoKit
import DocuVaultCore

/// Writes the plain-text mirror: vault/<person>/<type>-<title>.md, vault/index.md, expenses.csv, optional images/.
/// Always writes inside the app container. Also writes to a user-chosen folder when `syncFolder` is on.
@MainActor @Observable
final class ExportManager {
    static let shared = ExportManager()

    private let defaults = UserDefaults.standard
    private let bookmarkKey = "export.folder.bookmark"
    private let syncKey = "export.sync"
    private let imagesKey = "export.images"

    var syncFolder: Bool { didSet { defaults.set(syncFolder, forKey: syncKey) } }
    var includeImages: Bool { didSet { defaults.set(includeImages, forKey: imagesKey) } }
    private(set) var folderName: String?
    private(set) var lastExport: Date?
    private(set) var lastError: String?

    init() {
        syncFolder = defaults.bool(forKey: syncKey)
        includeImages = defaults.bool(forKey: imagesKey)
        folderName = resolveFolder()?.lastPathComponent
    }

    /// In-app mirror lives next to the database (Complete protection, inside the App Group).
    var inAppExportRoot: URL { AppFiles.containerURL.appendingPathComponent("Export", isDirectory: true) }

    // MARK: Folder bookmark

    func setFolder(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else { lastError = "No access to that folder."; return }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let bm = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(bm, forKey: bookmarkKey)
            folderName = url.lastPathComponent
            lastError = nil
        } catch { lastError = error.localizedDescription }
    }

    func clearFolder() { defaults.removeObject(forKey: bookmarkKey); folderName = nil }

    private func resolveFolder() -> URL? {
        guard let bm = defaults.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bm, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(fresh, forKey: bookmarkKey)
        }
        return url
    }

    // MARK: Export

    /// Rebuild the whole mirror. Sealed documents are written only when `vaultKey` is present; others are skipped with a note in index.md.
    func exportAll(context: ModelContext, vaultKey: SymmetricKey?) {
        lastError = nil
        let docs = (try? context.fetch(FetchDescriptor<StoredDocument>())) ?? []
        let tombstones = ((try? context.fetch(FetchDescriptor<StoredTombstone>())) ?? []).sorted { $0.deletedAt > $1.deletedAt }.map(\.line)
        var files: [(String, Data)] = []
        var rows: [MarkdownExporter.IndexRow] = []
        var csv = ""
        var skipped = 0

        for doc in docs.sorted(by: { $0.capturedAt < $1.capturedAt }) where doc.deletedAt == nil {
            let owner = doc.person?.name ?? (doc.sensitive ? "Unassigned" : "Library")
            let kind = doc.person?.kind ?? .other
            var fields: [ExtractedField] = []
            var readable = true
            for f in doc.orderedFields {
                var e = f.asExtracted
                if let sealed = f.sealedValue {
                    guard let key = vaultKey, let v = try? VaultCrypto.openString(sealed, key: key) else { readable = false; break }
                    e.value = v
                }
                fields.append(e)
            }
            guard readable else { skipped += 1; continue }

            let path = MarkdownExporter.relativePath(owner: owner, type: doc.type, title: doc.title)
            var imageNames: [String] = []
            if includeImages {
                for (i, p) in doc.orderedPages.enumerated() {
                    if let bytes = PageStore.jpegBytes(p.imageFileName, vaultKey: vaultKey) {
                        let name = "images/\(MarkdownExporter.slug(owner))/\(MarkdownExporter.slug(doc.title))-\(i + 1).jpg"
                        files.append((name, bytes)); imageNames.append(name)
                    }
                }
            }
            let export = ExportDocument(title: doc.title, owner: owner, ownerKind: kind, type: doc.type, sensitive: doc.sensitive,
                                        capturedAt: doc.capturedAt, source: doc.source.displayName, language: doc.language,
                                        checksPassed: doc.checksPassed, checksTotal: doc.checksTotal, fields: fields,
                                        expiresAt: doc.expiresAt, notes: doc.notes, imageFileNames: imageNames,
                                        summary: doc.summaryJSON.flatMap { try? JSONDecoder().decode(DocumentSummary.self, from: $0) })
            files.append((path, Data(MarkdownExporter.markdown(for: export).utf8)))

            let expiry = fields.first { ["expiry", "validTo", "expiryDate"].contains($0.key) }?.value
            let checks = doc.checksTotal == 0 ? "—" : "\(doc.checksPassed)/\(doc.checksTotal)"
            rows.append(.init(owner: owner, kind: kind, title: doc.title, type: doc.type, expiry: expiry.flatMap { $0.isEmpty ? nil : $0 }, checks: checks, path: path))

            if doc.type == .receipt {
                let r = ExtractionResult(type: .receipt, fields: fields)
                csv = MarkdownExporter.appendCSV(existing: csv, row: ReceiptExtractor.csvRow(r))
            }
        }
        var tomb = tombstones
        if skipped > 0 { tomb.append("- \(skipped) sealed document(s) not exported: vault was locked") }
        files.append(("vault/index.md", Data(MarkdownExporter.index(rows: rows, tombstones: tomb, generatedAt: Date()).utf8)))
        if !csv.isEmpty { files.append(("expenses.csv", Data(csv.utf8))) }

        write(files, to: inAppExportRoot, replaceTree: true)
        if syncFolder, let folder = resolveFolder() {
            guard folder.startAccessingSecurityScopedResource() else { lastError = "Folder access expired. Pick it again."; return }
            defer { folder.stopAccessingSecurityScopedResource() }
            write(files, to: folder.appendingPathComponent("DocuVault", isDirectory: true), replaceTree: true)
        }
        lastExport = Date()
    }

    private func write(_ files: [(String, Data)], to root: URL, replaceTree: Bool) {
        let fm = FileManager.default
        do {
            if replaceTree, fm.fileExists(atPath: root.path) {
                // Remove only what we own: vault/, images/, index + csv. Never touch other files in a user folder.
                for sub in ["vault", "images", "expenses.csv"] { try? fm.removeItem(at: root.appendingPathComponent(sub)) }
            }
            for (rel, data) in files {
                let url = root.appendingPathComponent(rel)
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            }
        } catch { lastError = error.localizedDescription }
    }
}
