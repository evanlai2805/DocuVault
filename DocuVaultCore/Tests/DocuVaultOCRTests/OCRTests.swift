import XCTest
import CoreGraphics
@testable import DocuVaultOCR
@testable import DocuVaultCore

final class OCREngineTests: XCTestCase {

    func testEnglishProse() async throws {
        let img = TestImageFactory.image(lines: ["SINGAPORE AIRLINES", "Total SGD 412.00", "SINGAPORE 460123"])
        let page = try await OCREngine.shared.recognize(img, mode: .prose)
        let text = page.text
        XCTAssertTrue(text.contains("412.00"), text)
        XCTAssertTrue(text.contains("460123"), text)
        XCTAssertEqual(page.language, "en")
        XCTAssertGreaterThan(page.meanConfidence, 0.5)
        XCTAssertEqual(page.readingOrder.first?.text.uppercased().contains("SINGAPORE"), true)
    }

    func testSimplifiedChinese() async throws {
        let img = TestImageFactory.image(lines: ["租赁合同", "甲方 西安某某制造有限公司", "乙方 李某某"],
                                         fontName: "PingFangSC-Regular", fontSize: 72)
        let page = try await OCREngine.shared.recognize(img, mode: .prose)
        XCTAssertTrue(page.text.contains("租赁合同"), page.text)
        XCTAssertTrue(page.text.contains("有限公司"), page.text)
        XCTAssertEqual(page.language, "zh-Hans")
    }

    func testAutoModePicksIdentityForMRZ() async throws {
        let l1 = MRZ.buildLine1(issuingCountry: "SGP", surname: "TAN", givenNames: "EVAN")
        let l2 = MRZ.buildLine2(documentNumber: "K1234567A", nationality: "SGP", dateOfBirth: "990412", sex: "M", expiry: "310228")
        let img = TestImageFactory.image(lines: ["REPUBLIC OF SINGAPORE PASSPORT", l1, l2],
                                         width: 2400, height: 600, fontName: "Menlo-Regular", fontSize: 48)
        let page = try await OCREngine.shared.recognize(img, mode: .auto)
        XCTAssertEqual(page.mode, .identity, page.text)
        // Vision may split or merge lines; locate on the normalised text lines.
        let found = MRZ.locateLines(in: page.textLines)
        XCTAssertNotNil(found, page.text)
        if let (a, b) = found {
            let td3 = try MRZ.parseTD3(line1: a, line2: b)
            XCTAssertEqual(td3.documentNumber, "K1234567A", page.text)
            XCTAssertTrue(td3.allChecksOK, "\(a)\n\(b)")
        }
    }

    func testIdentityHeuristic() {
        XCTAssertTrue(OCREngine.looksLikeIdentityDocument(["IDENTITY CARD NO. S9912345A"]))
        XCTAssertTrue(OCREngine.looksLikeIdentityDocument(["4111 1111 1111 1111", "VALID THRU 09/29"]))
        XCTAssertTrue(OCREngine.looksLikeIdentityDocument(["公民身份号码 11010519491231002X"]))
        XCTAssertFalse(OCREngine.looksLikeIdentityDocument(["Dear Sir", "Please find attached the invoice."]))
    }
}

final class ImageNormalizerTests: XCTestCase {

    func testRotateSwapsDimensions() {
        let img = TestImageFactory.image(lines: ["A"], width: 300, height: 100)
        let r = ImageNormalizer.rotated(img, quarterTurnsClockwise: 1)!
        XCTAssertEqual(r.width, 100)
        XCTAssertEqual(r.height, 300)
        XCTAssertEqual(ImageNormalizer.rotated(img, quarterTurnsClockwise: 4)!.width, 300)
    }

    func testJPEGRoundTripAndDownscale() {
        let img = TestImageFactory.image(lines: ["Big"], width: 4000, height: 2000)
        let data = ImageNormalizer.jpegData(img)!
        XCTAssertGreaterThan(data.count, 1000)
        let reloaded = ImageNormalizer.load(data: data)!
        XCTAssertLessThanOrEqual(max(reloaded.width, reloaded.height), ImageNormalizer.maxLongEdge)
        XCTAssertEqual(Double(reloaded.width) / Double(reloaded.height), 2.0, accuracy: 0.01)
    }

    func testGreyscale() {
        let img = TestImageFactory.image(lines: ["x"], width: 50, height: 50)
        let g = ImageNormalizer.greyscale(img)!
        XCTAssertEqual(g.colorSpace?.model, .monochrome)
    }
}

final class PDFImporterTests: XCTestCase {

    func testTextPDFKeepsEmbeddedText() throws {
        let data = TestImageFactory.pdf(lines: ["Lease Agreement between Party A and Party B", "Term: 1 Jan 2026 to 31 Dec 2028"], drawText: true)
        let pages = try PDFImporter.importPDF(data: data)
        XCTAssertEqual(pages.count, 1)
        XCTAssertNotNil(pages[0].embeddedText)
        XCTAssertTrue(pages[0].embeddedText!.contains("Lease Agreement"))
        XCTAssertGreaterThan(pages[0].image.width, 1000)   // rendered at 200 dpi
    }

    func testScannedPDFHasNoTextAndRenders() throws {
        let data = TestImageFactory.pdf(lines: [], drawText: false)
        let pages = try PDFImporter.importPDF(data: data)
        XCTAssertEqual(pages.count, 1)
        XCTAssertNil(pages[0].embeddedText)
        XCTAssertLessThanOrEqual(max(pages[0].image.width, pages[0].image.height), ImageNormalizer.maxLongEdge)
    }

    func testGarbageThrows() {
        XCTAssertThrowsError(try PDFImporter.importPDF(data: Data("not a pdf".utf8)))
    }
}

final class TitleGuesserTests: XCTestCase {
    func testChineseTitle() {
        XCTAssertEqual(TitleGuesser.guess(from: ["2026年1月1日", "租赁合同", "甲方…"]), "租赁合同")
    }
    func testEnglishTitleSkipsNoise() {
        XCTAssertEqual(TitleGuesser.guess(from: ["10/10/2026", "SGD 412.00", "Singapore Airlines Receipt", "Booking ref 7XK2PQ"]),
                       "Singapore Airlines Receipt")
    }
    func testMRZIsNotATitle() {
        let mrz = "P<SGPTAN<<EVAN<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<"
        XCTAssertEqual(TitleGuesser.guess(from: [mrz, "REPUBLIC OF SINGAPORE"]), "REPUBLIC OF SINGAPORE")
    }
    func testFallback() {
        XCTAssertEqual(TitleGuesser.guess(from: []), "Untitled")
        XCTAssertEqual(TitleGuesser.guess(from: ["12345"]), "12345")
    }
    func testClip() {
        let long = String(repeating: "word ", count: 30)
        XCTAssertLessThanOrEqual(TitleGuesser.guess(from: [long]).count, TitleGuesser.maxLength)
    }
}
