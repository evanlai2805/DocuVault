import Foundation
import SwiftUI
import UserNotifications
import DocuVaultCore
#if canImport(MLXLLM)
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import Tokenizers
#endif

/// Qwen via MLX for Chinese-heavy documents (checkpoint 18). The files come from `ModelDownloader`: a
/// background download of one pinned, hash-checked revision into Application Support. Apple's model
/// stays the fallback whenever Qwen is absent, disabled, or fails.
@MainActor @Observable
final class LocalModelManager {
    static let shared = LocalModelManager()

    enum State: Equatable {
        case unavailable(String)                       // not on this device or build
        case notInstalled
        case downloading(received: Int64, total: Int64)
        case paused(received: Int64, total: Int64)
        case verifying                                 // checking hashes before install
        case installed                                 // files in place, not loaded
        case loading
        case ready
        case failed(String)
    }
    private(set) var state: State = .notInstalled
    /// Bytes per second, smoothed, for "About 3 min left".
    private(set) var rate: Double = 0
    var useForChinese: Bool { didSet { UserDefaults.standard.set(useForChinese, forKey: "mlx.useForChinese") } }
    /// The summary card offers the model once (Q1). Set when it has been shown and answered.
    var offerAnswered: Bool { didSet { UserDefaults.standard.set(offerAnswered, forKey: "mlx.offerAnswered") } }

    let downloader = ModelDownloader.shared
    var totalBytes: Int64 { downloader.manifest.totalBytes }
    private var lastSample: (bytes: Int64, at: Date)?

    #if canImport(MLXLLM)
    private var container: ModelContainer?
    #endif

    init() {
        useForChinese = UserDefaults.standard.object(forKey: "mlx.useForChinese") as? Bool ?? true
        offerAnswered = UserDefaults.standard.bool(forKey: "mlx.offerAnswered")
        #if targetEnvironment(simulator)
        // MLX needs a real GPU; its troubleshooting guide says the Simulator cannot run it, and loading
        // there crashes (seen 13 Oct).
        state = .unavailable("Runs on iPhone only")
        #elseif canImport(MLXLLM)
        state = downloader.isInstalled ? .installed : .notInstalled
        downloader.onEvent = { [weak self] event in Task { @MainActor in self?.handle(event) } }
        Task { await reconnect() }
        #else
        state = .unavailable("Not in this build")
        #endif
    }

    var isInstalled: Bool {
        switch state { case .installed, .loading, .ready: true; default: false }
    }
    var installedSizeGB: Double { Double(totalBytes) / 1_000_000_000 }

    /// Can we answer a Chinese summary with Qwen right now (or after a load)?
    var canServeChinese: Bool { useForChinese && isInstalled }

    // MARK: Download

    /// Pick up a download that ran while the app was closed, or leftovers of an older attempt.
    private func reconnect() async {
        guard !downloader.isInstalled else { return }
        if downloader.legacyCacheIsComplete {
            state = .verifying
            let d = downloader
            Task.detached { d.importLegacyCache(); d.installStaged() }
            return
        }
        if let r = await downloader.reattach() {
            state = r.paused ? .paused(received: r.received, total: totalBytes) : .downloading(received: r.received, total: totalBytes)
        }
    }

    func download(allowCellular: Bool) async {
        #if canImport(MLXLLM) && !targetEnvironment(simulator)
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        state = .downloading(received: currentReceived, total: totalBytes)
        lastSample = nil
        rate = 0
        await downloader.start(allowCellular: allowCellular)
        #endif
    }

    func pause() async {
        await downloader.pause()
        state = .paused(received: currentReceived, total: totalBytes)
        rate = 0
    }

    func delete() async {
        #if canImport(MLXLLM)
        container = nil
        #endif
        await downloader.removeAll()
        state = .notInstalled
    }

    private var currentReceived: Int64 {
        switch state {
        case .downloading(let r, _), .paused(let r, _): r
        default: 0
        }
    }

    private func handle(_ event: ModelDownloader.Event) {
        switch event {
        case .progress(let received):
            if case .paused = state { return }
            let now = Date()
            if let s = lastSample, now.timeIntervalSince(s.at) >= 1 {
                let instant = Double(received - s.bytes) / now.timeIntervalSince(s.at)
                rate = rate == 0 ? instant : rate * 0.8 + instant * 0.2
                lastSample = (received, now)
            } else if lastSample == nil {
                lastSample = (received, now)
            }
            state = .downloading(received: received, total: totalBytes)
        case .verifying:
            state = .verifying
        case .installed:
            state = .installed
            rate = 0
            notifyReady()
        case .failed(let message):
            state = .failed(message)
            rate = 0
        }
    }

    /// Only when the app is not on screen; on screen, the Summaries page already shows it.
    private func notifyReady() {
        guard UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = "Chinese model ready"
        content.body = "Summaries of Chinese documents now run on this iPhone."
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "model-ready", content: content, trigger: nil))
    }

    // MARK: Load

    #if canImport(MLXLLM)
    /// Load from the installed folder. Cached for the session; freed on memory pressure by `unload()`.
    func load() async throws -> ModelContainer {
        if let c = container { return c }
        guard downloader.isInstalled else { throw SummarizerError.unavailable(.unknown("The Chinese model is not installed.")) }
        state = .loading
        do {
            let c = try await loadModelContainer(from: downloader.installedDirectory, using: #huggingFaceTokenizerLoader())
            container = c
            state = .ready
            return c
        } catch {
            state = .installed
            throw error
        }
    }

    func unload() {
        container = nil
        state = downloader.isInstalled ? .installed : .notInstalled
    }
    #endif
}
