import Foundation
import SwiftUI
import DocuVaultCore
#if canImport(MLXLLM)

import MLXLLM
import MLXLMCommon
#endif

/// Qwen via MLX for Chinese-heavy documents. One-time download (~2.5 GB) that you start from Settings.
/// Apple's model stays the fallback whenever Qwen is absent, disabled, or fails.
@MainActor @Observable
final class LocalModelManager {
    static let shared = LocalModelManager()

    /// 4-bit Qwen3 4B: strong Chinese, fits comfortably in the iPhone 17 Pro's memory.
    static let modelID = "mlx-community/Qwen3-4B-4bit"
    static let approxSizeGB = 2.5

    enum State: Equatable {
        case unavailable(String)      // framework missing from this build
        case notInstalled
        case downloading(Double)      // 0…1
        case installed                // files on disk, not loaded
        case loading
        case ready
        case failed(String)
    }
    private(set) var state: State = .notInstalled
    var useForChinese: Bool { didSet { UserDefaults.standard.set(useForChinese, forKey: "mlx.useForChinese") } }

    #if canImport(MLXLLM)
    private var container: ModelContainer?
    #endif

    init() {
        useForChinese = UserDefaults.standard.object(forKey: "mlx.useForChinese") as? Bool ?? true
        #if canImport(MLXLLM)
        state = isInstalled ? .installed : .notInstalled
        #else
        state = .unavailable("MLX not in this build")
        #endif
    }

    /// Hugging Face cache lives in the app's Documents. Installed = at least one weights file present.
    var modelDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("huggingface/models/\(Self.modelID)", isDirectory: true)
    }
    var isInstalled: Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: modelDirectory.path))?.contains { $0.hasSuffix(".safetensors") } ?? false
    }
    var installedSizeGB: Double {
        guard let files = try? FileManager.default.contentsOfDirectory(at: modelDirectory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        let bytes = files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return Double(bytes) / 1_073_741_824
    }

    /// Can we answer a Chinese summary with Qwen right now (or after a load)?
    var canServeChinese: Bool {
        guard useForChinese else { return false }
        switch state { case .installed, .ready, .loading: return true; default: return false }
    }

    // MARK: Download / load

    func download() async {
        #if canImport(MLXLLM)
        state = .downloading(0)
        do {
            _ = try await load(progressHandler: { [weak self] p in Task { @MainActor in self?.state = .downloading(p) } })
            state = .ready
        } catch {
            state = .failed("Download failed: \(error.localizedDescription)")
        }
        #endif
    }

    func delete() {
        #if canImport(MLXLLM)
        container = nil
        #endif
        try? FileManager.default.removeItem(at: modelDirectory)
        state = .notInstalled
    }

    #if canImport(MLXLLM)
    /// Load (downloading if needed). Cached for the session; freed on memory pressure by `unload()`.
    func load(progressHandler: ((Double) -> Void)? = nil) async throws -> ModelContainer {
        if let c = container { return c }
        if case .downloading = state {} else { state = .loading }
        let config = ModelConfiguration(id: Self.modelID)
        let c = try await LLMModelFactory.shared.loadContainer(configuration: config) { progress in
            progressHandler?(progress.fractionCompleted)
        }
        container = c
        state = .ready
        return c
    }

    func unload() {
        container = nil
        state = isInstalled ? .installed : .notInstalled
    }
    #endif
}
