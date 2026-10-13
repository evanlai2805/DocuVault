import Foundation
import DocuVaultCore

/// Downloads the Chinese model's pinned files with Apple's background download (checkpoint 18 Q3): it
/// carries on when DocuVault is closed, waits through a dropped connection, and relaunches the app in
/// the background when done. Files land in a staging folder, are checked against the manifest's hashes,
/// and only then move into place in one rename, so a half or altered download is never loaded.
/// The only network use is fetching these files from Hugging Face; no document ever leaves the phone.
final class ModelDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    // @unchecked: mutable state is guarded by `lock`; URLSession calls the delegate on its own queue.
    static let shared = ModelDownloader()
    static let sessionID = "com.evanlai.docuvault.model-download"
    let manifest = ModelManifest.qwen3_4B

    enum Event: Sendable {
        case progress(received: Int64)
        case verifying
        case installed
        case failed(String)
    }
    /// Set once by LocalModelManager; called on an arbitrary queue.
    var onEvent: (@Sendable (Event) -> Void)?

    private let lock = NSLock()
    private var inFlight: [String: Int64] = [:]          // file name → bytes written so far
    private var backgroundCompletion: (() -> Void)?
    private var finishing = false

    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.background(withIdentifier: Self.sessionID)
        c.isDiscretionary = false
        c.sessionSendsLaunchEvents = true
        return URLSession(configuration: c, delegate: self, delegateQueue: nil)
    }()

    // MARK: Folders

    /// Application Support, which iOS does not clear under storage pressure (Q5). Left out of iCloud backup.
    static var modelsRoot: URL { URL.applicationSupportDirectory.appendingPathComponent("Models", isDirectory: true) }
    var installedDirectory: URL { Self.modelsRoot.appendingPathComponent(manifest.folderName, isDirectory: true) }
    private var stagingDirectory: URL { Self.modelsRoot.appendingPathComponent(manifest.folderName + ".partial", isDirectory: true) }
    /// Where the library's own downloader used to put the files (before 13 Oct).
    static var legacyCache: URL {
        URL.cachesDirectory.appendingPathComponent("huggingface/hub/models--mlx-community--Qwen3-4B-4bit", isDirectory: true)
    }

    /// Cheap check used at launch: every file present at its expected size. Hashes were checked before
    /// the folder was moved into place.
    var isInstalled: Bool {
        manifest.files.allSatisfy { f in
            let url = installedDirectory.appendingPathComponent(f.name)
            return (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value == f.size
        }
    }

    // MARK: Control

    /// Reconnect to downloads that carried on while the app was closed. Returns bytes done so far when
    /// a download is running or paused, nil when none is.
    func reattach() async -> (received: Int64, paused: Bool)? {
        let tasks = await session.allTasks
        let staged = stagedBytes()
        if !tasks.isEmpty {
            lock.withLock { for t in tasks { if let n = t.taskDescription { inFlight[n] = t.countOfBytesReceived } } }
            return (staged + lock.withLock { inFlight.values.reduce(0, +) }, false)
        }
        if hasResumeData() { return (staged, true) }
        return nil
    }

    /// Start or continue. `allowCellular` false waits for Wi-Fi (frame 3, "Wait for Wi-Fi").
    func start(allowCellular: Bool) async {
        try? FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        Self.excludeFromBackup(Self.modelsRoot)
        importLegacyCache()
        if await !session.allTasks.isEmpty { return }
        var started = false
        for f in manifest.files where !isStaged(f) {
            let resume = stagingDirectory.appendingPathComponent(f.name + ".resume")
            let task: URLSessionDownloadTask
            if let data = try? Data(contentsOf: resume) {
                task = session.downloadTask(withResumeData: data)
                try? FileManager.default.removeItem(at: resume)
            } else {
                var req = URLRequest(url: manifest.url(for: f))
                req.allowsCellularAccess = allowCellular
                req.allowsExpensiveNetworkAccess = allowCellular
                task = session.downloadTask(with: req)
                task.countOfBytesClientExpectsToReceive = f.size
            }
            task.taskDescription = f.name
            task.resume()
            started = true
        }
        if !started { finishIfComplete() }
    }

    /// Pause keeps what has arrived; Resume carries on from there.
    func pause() async {
        for t in await session.allTasks {
            guard let d = t as? URLSessionDownloadTask, let name = d.taskDescription else { continue }
            if let data = await d.cancelByProducingResumeData() {
                try? data.write(to: stagingDirectory.appendingPathComponent(name + ".resume"))
            }
        }
    }

    /// Cancel and remove everything, including an installed model.
    func removeAll() async {
        for t in await session.allTasks { t.cancel() }
        lock.withLock { inFlight = [:] }
        try? FileManager.default.removeItem(at: stagingDirectory)
        try? FileManager.default.removeItem(at: installedDirectory)
        try? FileManager.default.removeItem(at: Self.legacyCache)
    }

    /// For SwiftUI's `.backgroundTask(.urlSession(...))`: iOS relaunched the app to deliver results.
    func handleBackgroundEvents() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            lock.withLock { backgroundCompletion = { c.resume() } }
            _ = session   // recreating the session with the same identifier reconnects it
        }
    }

    // MARK: URLSession delegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let name = downloadTask.taskDescription else { return }
        let total = lock.withLock { () -> Int64 in
            inFlight[name] = totalBytesWritten
            return inFlight.values.reduce(0, +)
        }
        onEvent?(.progress(received: stagedBytes() + total))
    }

    /// The file must be moved before this returns; iOS deletes `location` afterwards.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let name = downloadTask.taskDescription else { return }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { return }   // reported in didCompleteWithError below
        let dest = stagingDirectory.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.moveItem(at: location, to: dest)
        lock.withLock { inFlight[name] = nil }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let name = task.taskDescription ?? ""
        if let error = error as NSError? {
            if let data = error.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                try? data.write(to: stagingDirectory.appendingPathComponent(name + ".resume"))
            }
            if error.code == NSURLErrorCancelled { return }   // Pause
            onEvent?(.failed(Self.describe(error)))
            return
        }
        if let status = (task.response as? HTTPURLResponse)?.statusCode, status != 200 {
            onEvent?(.failed("The model server answered \(status). Try again later."))
            return
        }
        finishIfComplete()
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let done = lock.withLock { () -> (() -> Void)? in
            defer { backgroundCompletion = nil }
            return backgroundCompletion
        }
        DispatchQueue.main.async { done?() }
    }

    // MARK: Finishing

    /// Every file staged: check each hash, then move the folder into place in one rename.
    private func finishIfComplete() {
        guard manifest.files.allSatisfy(isStaged) else { return }
        let begin = lock.withLock { () -> Bool in
            if finishing { return false }
            finishing = true
            return true
        }
        guard begin else { return }
        onEvent?(.verifying)
        defer { lock.withLock { finishing = false } }
        for f in manifest.files where !ModelManifest.verify(stagingDirectory.appendingPathComponent(f.name), against: f) {
            try? FileManager.default.removeItem(at: stagingDirectory.appendingPathComponent(f.name))
            onEvent?(.failed("A downloaded file did not match. It will download again."))
            return
        }
        let fm = FileManager.default
        try? fm.removeItem(at: installedDirectory)
        for f in (try? fm.contentsOfDirectory(atPath: stagingDirectory.path)) ?? [] where f.hasSuffix(".resume") {
            try? fm.removeItem(at: stagingDirectory.appendingPathComponent(f))
        }
        do { try fm.moveItem(at: stagingDirectory, to: installedDirectory) } catch {
            onEvent?(.failed("Could not finish installing. Try again."))
            return
        }
        Self.excludeFromBackup(installedDirectory)
        try? fm.removeItem(at: Self.legacyCache)
        onEvent?(.installed)
    }

    private func isStaged(_ f: ModelManifest.File) -> Bool {
        let url = stagingDirectory.appendingPathComponent(f.name)
        return (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value == f.size
    }

    private func stagedBytes() -> Int64 { manifest.files.filter(isStaged).reduce(0) { $0 + $1.size } }

    private func hasResumeData() -> Bool {
        ((try? FileManager.default.contentsOfDirectory(atPath: stagingDirectory.path)) ?? []).contains { $0.hasSuffix(".resume") }
    }

    /// An earlier attempt may have left complete files in Caches. Move any with the right size into
    /// staging; the hash check before install decides whether they are kept.
    func importLegacyCache() {
        let snapshots = Self.legacyCache.appendingPathComponent("snapshots", isDirectory: true)
        guard let revs = try? FileManager.default.contentsOfDirectory(atPath: snapshots.path) else { return }
        try? FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        for rev in revs {
            for f in manifest.files where !isStaged(f) {
                let src = snapshots.appendingPathComponent(rev).appendingPathComponent(f.name).resolvingSymlinksInPath()
                guard (try? FileManager.default.attributesOfItem(atPath: src.path)[.size] as? NSNumber)?.int64Value == f.size else { continue }
                try? FileManager.default.moveItem(at: src, to: stagingDirectory.appendingPathComponent(f.name))
            }
        }
    }

    /// True when the leftovers in Caches already hold every file at the right size.
    var legacyCacheIsComplete: Bool {
        let snapshots = Self.legacyCache.appendingPathComponent("snapshots", isDirectory: true)
        guard let revs = try? FileManager.default.contentsOfDirectory(atPath: snapshots.path) else { return false }
        return revs.contains { rev in
            manifest.files.allSatisfy { f in
                let src = snapshots.appendingPathComponent(rev).appendingPathComponent(f.name).resolvingSymlinksInPath()
                return (try? FileManager.default.attributesOfItem(atPath: src.path)[.size] as? NSNumber)?.int64Value == f.size
            }
        }
    }

    /// Re-run the finish step for files already staged (used after importing leftovers).
    func installStaged() { finishIfComplete() }

    static func excludeFromBackup(_ url: URL) {
        var u = url
        var v = URLResourceValues()
        v.isExcludedFromBackup = true
        try? u.setResourceValues(v)
    }

    /// One line that says what happened, never "The operation couldn't be completed".
    static func describe(_ e: NSError) -> String {
        switch e.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost: return "No connection · Resumes when you are back online"
        case NSURLErrorTimedOut: return "The connection timed out · Tap Resume to carry on"
        case NSURLErrorCannotWriteToFile, NSURLErrorDataLengthExceedsMaximum: return "Not enough free space · Free some, then Resume"
        default: return "The download stopped · Tap Resume to carry on"
        }
    }
}
