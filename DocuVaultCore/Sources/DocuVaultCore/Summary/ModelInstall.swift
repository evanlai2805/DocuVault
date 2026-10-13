import Foundation
import CryptoKit

/// The Chinese summary model's files, pinned to one revision of the Hugging Face repository, each with
/// the hash Hugging Face publishes (checkpoint 18). A file only counts as installed once its hash matches,
/// so a cut-off or altered download is never loaded.
public struct ModelManifest: Sendable, Equatable {
    public enum Check: Sendable, Equatable {
        case sha256(String)        // large files kept in Git LFS: SHA-256 of the content
        case gitBlobSHA1(String)   // small files: Git's blob hash, SHA-1 of "blob <size>\0" + content
    }
    public struct File: Sendable, Equatable {
        public let name: String
        public let size: Int64
        public let check: Check
    }

    public let repo: String
    public let revision: String
    public let files: [File]

    public var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }
    public var folderName: String { repo.split(separator: "/").last.map(String.init)! + "-" + revision.prefix(8) }

    public func url(for file: File) -> URL {
        URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(file.name)")!
    }

    /// mlx-community/Qwen3-4B-4bit at 4dcb3d10, the files MLX loads (*.safetensors, *.json). Sizes and
    /// hashes read from the Hugging Face tree API on 13 Oct 2026.
    public static let qwen3_4B = ModelManifest(
        repo: "mlx-community/Qwen3-4B-4bit",
        revision: "4dcb3d101c2a062e5c1d4bb173588c54ea6c4d25",
        files: [
            File(name: "model.safetensors", size: 2_263_022_529, check: .sha256("e240c0bdc0ebb0681bf0da0f98d9719fd6ebe269a3633f81542c13e81345651d")),
            File(name: "tokenizer.json", size: 11_422_654, check: .sha256("aeb13307a71acd8fe81861d94ad54ab689df773318809eed3cbe794b4492dae4")),
            File(name: "vocab.json", size: 2_776_833, check: .gitBlobSHA1("4783fe10ac3adce15ac8f358ef5462739852c569")),
            File(name: "model.safetensors.index.json", size: 63_924, check: .gitBlobSHA1("07e230a328dd17a09d96ee045d49b27596656aff")),
            File(name: "tokenizer_config.json", size: 9_706, check: .gitBlobSHA1("7345216a0785dc7086e8c245b2a9d3896ce2b756")),
            File(name: "config.json", size: 937, check: .gitBlobSHA1("032ad326a0daaaeeec00f2a585262acf5f692861")),
            File(name: "added_tokens.json", size: 707, check: .gitBlobSHA1("b54f9135e44c1e81047e8d05cb027af8bc039eed")),
            File(name: "special_tokens_map.json", size: 613, check: .gitBlobSHA1("ac23c0aaa2434523c494330aeb79c58395378103")),
        ])

    /// True when the file on disk has the expected size and hash. Reads in 4 MB pieces, so the 2.3 GB
    /// weights never sit in memory at once.
    public static func verify(_ url: URL, against file: File) -> Bool {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value,
              size == file.size,
              let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        switch file.check {
        case .sha256(let want):
            var h = SHA256()
            while let chunk = try? handle.read(upToCount: 4 << 20), !chunk.isEmpty { h.update(data: chunk) }
            return hex(h.finalize()) == want
        case .gitBlobSHA1(let want):
            var h = Insecure.SHA1()
            h.update(data: Data("blob \(size)\0".utf8))
            while let chunk = try? handle.read(upToCount: 4 << 20), !chunk.isEmpty { h.update(data: chunk) }
            return hex(h.finalize()) == want
        }
    }

    static func hex<D: Digest>(_ d: D) -> String { d.map { String(format: "%02x", $0) }.joined() }
}

/// The phone checks before a 2.5 GB download (checkpoint 18 frame 3). Pure, so it is tested.
public enum InstallCheck {
    public enum Tone: Sendable, Equatable { case ok, warn, stop }
    public struct Item: Sendable, Equatable {
        public let label: String
        public let value: String
        public let tone: Tone
    }
    public enum Connection: Sendable, Equatable { case wifi, cellular, none }

    /// Below this, the download does not start: the model plus room for iOS to keep working.
    public static let minimumFreeBytes: Int64 = 5_000_000_000

    public static func items(freeBytes: Int64, connection: Connection, battery: Double?, charging: Bool, downloadBytes: Int64) -> [Item] {
        var out: [Item] = []
        let free = gigabytes(freeBytes, digits: 0)
        if freeBytes < minimumFreeBytes {
            out.append(Item(label: "Free space", value: "\(free) · Free up \(gigabytes(minimumFreeBytes - freeBytes, digits: 1))", tone: .stop))
        } else {
            out.append(Item(label: "Free space", value: free, tone: .ok))
        }
        switch connection {
        case .wifi: out.append(Item(label: "Connection", value: "Wi-Fi", tone: .ok))
        case .cellular: out.append(Item(label: "Connection", value: "Mobile data · Uses \(gigabytes(downloadBytes, digits: 1))", tone: .warn))
        case .none: out.append(Item(label: "Connection", value: "Offline · Starts when connected", tone: .warn))
        }
        if let b = battery {
            let pct = "\(Int((b * 100).rounded()))%"
            if charging { out.append(Item(label: "Battery", value: "\(pct) · Charging", tone: .ok)) }
            else if b < 0.2 { out.append(Item(label: "Battery", value: "\(pct) · Plug in first", tone: .warn)) }
            else { out.append(Item(label: "Battery", value: pct, tone: .ok)) }
        }
        return out
    }

    public static func canStart(_ items: [Item]) -> Bool { !items.contains { $0.tone == .stop } }

    /// "2.3 GB", "48 GB". Decimal gigabytes, as iOS Settings shows storage.
    public static func gigabytes(_ bytes: Int64, digits: Int) -> String {
        String(format: "%.\(digits)f GB", Double(max(bytes, 0)) / 1_000_000_000)
    }

    /// "1.6 of 2.3 GB" and, once the rate is known, "About 3 min left".
    public static func progressLine(received: Int64, total: Int64) -> String {
        String(format: "%.1f of %.1f GB", Double(max(received, 0)) / 1_000_000_000, Double(total) / 1_000_000_000)
    }

    public static func timeLeft(received: Int64, total: Int64, bytesPerSecond: Double) -> String? {
        guard bytesPerSecond > 1, total > received else { return nil }
        let seconds = Double(total - received) / bytesPerSecond
        if seconds < 60 { return "Less than a minute left" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "About \(minutes) min left" }
        return "About \(minutes / 60) h \(minutes % 60) min left"
    }
}
