import XCTest
@testable import DocuVaultCore

/// Checkpoint 18: the Chinese model's file checks, the phone checks before download, the progress wording.
final class ModelInstallTests: XCTestCase {

    private func temp(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(contents.utf8).write(to: url)
        return url
    }

    // Published specimen: `printf 'hello\n' | git hash-object --stdin` = ce013625…
    func testGitBlobHashMatchesGit() throws {
        let url = try temp("hello\n")
        let file = ModelManifest.File(name: "x", size: 6, check: .gitBlobSHA1("ce013625030ba8dba906f756967f9e9ca394464a"))
        XCTAssertTrue(ModelManifest.verify(url, against: file))
    }

    // Published specimen: SHA-256("abc") = ba7816bf…
    func testSHA256MatchesSpecimen() throws {
        let url = try temp("abc")
        let file = ModelManifest.File(name: "x", size: 3, check: .sha256("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"))
        XCTAssertTrue(ModelManifest.verify(url, against: file))
    }

    func testWrongSizeOrHashFails() throws {
        let url = try temp("abd")
        XCTAssertFalse(ModelManifest.verify(url, against: .init(name: "x", size: 3, check: .sha256("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"))))
        XCTAssertFalse(ModelManifest.verify(url, against: .init(name: "x", size: 4, check: .sha256("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"))))
        XCTAssertFalse(ModelManifest.verify(URL(fileURLWithPath: "/nonexistent"), against: .init(name: "x", size: 3, check: .sha256(""))))
    }

    func testQwenManifestIsPinned() {
        let m = ModelManifest.qwen3_4B
        XCTAssertEqual(m.files.count, 8)
        XCTAssertEqual(m.totalBytes, 2_277_297_903)
        XCTAssertEqual(m.url(for: m.files[0]).absoluteString,
                       "https://huggingface.co/mlx-community/Qwen3-4B-4bit/resolve/4dcb3d101c2a062e5c1d4bb173588c54ea6c4d25/model.safetensors")
        XCTAssertEqual(m.folderName, "Qwen3-4B-4bit-4dcb3d10")
    }

    func testChecksStopOnLowSpaceAndWarnOnMobileData() {
        let low = InstallCheck.items(freeBytes: 3_000_000_000, connection: .wifi, battery: 0.8, charging: false, downloadBytes: 2_300_000_000)
        XCTAssertEqual(low[0], .init(label: "Free space", value: "3 GB · Free up 2.0 GB", tone: .stop))
        XCTAssertFalse(InstallCheck.canStart(low))

        let cell = InstallCheck.items(freeBytes: 48_000_000_000, connection: .cellular, battery: 0.8, charging: false, downloadBytes: 2_277_298_903)
        XCTAssertEqual(cell[1], .init(label: "Connection", value: "Mobile data · Uses 2.3 GB", tone: .warn))
        XCTAssertEqual(cell[2], .init(label: "Battery", value: "80%", tone: .ok))
        XCTAssertTrue(InstallCheck.canStart(cell))
    }

    func testLowBatteryWarnsUnlessCharging() {
        XCTAssertEqual(InstallCheck.items(freeBytes: 48_000_000_000, connection: .wifi, battery: 0.1, charging: false, downloadBytes: 1)[2].tone, .warn)
        XCTAssertEqual(InstallCheck.items(freeBytes: 48_000_000_000, connection: .wifi, battery: 0.1, charging: true, downloadBytes: 1)[2].value, "10% · Charging")
    }

    func testProgressWording() {
        XCTAssertEqual(InstallCheck.progressLine(received: 1_600_000_000, total: 2_277_298_903), "1.6 of 2.3 GB")
        XCTAssertEqual(InstallCheck.timeLeft(received: 0, total: 2_000_000_000, bytesPerSecond: 10_000_000), "About 3 min left")
        XCTAssertEqual(InstallCheck.timeLeft(received: 0, total: 100_000_000, bytesPerSecond: 10_000_000), "Less than a minute left")
        XCTAssertEqual(InstallCheck.timeLeft(received: 0, total: 3_600_000_000, bytesPerSecond: 500_000), "About 2 h 0 min left")
        XCTAssertNil(InstallCheck.timeLeft(received: 5, total: 5, bytesPerSecond: 100))
    }
}
