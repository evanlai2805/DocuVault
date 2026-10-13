import XCTest
@testable import DocuVaultCore

final class FieldEditTests: XCTestCase {

    // MARK: Display dates (checkpoint 14 Q3)

    func testDisplayDate() {
        XCTAssertEqual(FillFormats.display("1990-03-12"), "12/MAR/1990")
        XCTAssertEqual(FillFormats.display("2031-12-05"), "05/DEC/2031")
        XCTAssertEqual(FillFormats.display("长期"), "长期")
        XCTAssertEqual(FillFormats.display("09/29"), "09/29")
    }

    func testMonthNameStyles() {
        XCTAssertEqual(FillFormats.date("1999-04-12", style: .dMonYSlash), "12/APR/1999")
        XCTAssertEqual(FillFormats.date("1999-04-12", style: .dMonYDash), "12-APR-1999")
        XCTAssertEqual(FillFormats.DateStyle.allCases.count, 8)
        XCTAssertEqual(FillFormats.DateStyle.allCases.first, .dmySlash)
    }

    // MARK: Normalise

    func testDisplayFormatParsesBackToISO() {
        // The edit sheet shows 12/MAR/1990; saving must store ISO again.
        XCTAssertEqual(FieldEdit.normalize(key: "dateOfBirth", value: "12/MAR/1990", type: .passport), "1990-03-12")
        XCTAssertEqual(FieldEdit.normalize(key: "dateOfBirth", value: "12-MAR-1990", type: .passport), "1990-03-12")
        XCTAssertEqual(FieldEdit.normalize(key: "expiry", value: " 05 MAR 2031 ", type: .passport), "2031-03-05")
        XCTAssertEqual(FieldEdit.normalize(key: "dateOfBirth", value: "12/03/1990", type: .nric), "1990-03-12")
    }

    func testNormalizeLeavesNonDatesAlone() {
        XCTAssertEqual(FieldEdit.normalize(key: "validTo", value: "长期", type: .chinaID), "长期")
        XCTAssertEqual(FieldEdit.normalize(key: "expiry", value: "09/29", type: .bankCard), "09/29")
        XCTAssertEqual(FieldEdit.normalize(key: "givenNames", value: " CELINE ", type: .passport), "CELINE")
        XCTAssertEqual(FieldEdit.normalize(key: "pan", value: "4111 1111 1111 1111", type: .bankCard), "4111111111111111")
    }

    // MARK: Recheck, with the published specimens the checker tests already use

    func testRecheckRunsChecksums() {
        XCTAssertEqual(FieldEdit.recheck(key: "nric", value: "S9912345A", type: .nric), .nric)
        XCTAssertEqual(FieldEdit.recheck(key: "nric", value: "S9912345B", type: .nric), .ocr)
        XCTAssertEqual(FieldEdit.recheck(key: "pan", value: "4111111111111111", type: .bankCard), .luhn)
        XCTAssertEqual(FieldEdit.recheck(key: "pan", value: "4111111111111112", type: .bankCard), .ocr)
        XCTAssertEqual(FieldEdit.recheck(key: "idNumber", value: "11010519491231002X", type: .chinaID), .cnid)
        XCTAssertEqual(FieldEdit.recheck(key: "idNumber", value: "110105194912310021", type: .chinaID), .ocr)
    }

    func testRecheckOtherFields() {
        XCTAssertEqual(FieldEdit.recheck(key: "passportNumber", value: "K1234567", type: .passport), .user)
        XCTAssertEqual(FieldEdit.recheck(key: "givenNames", value: "CELINE", type: .passport), .user)
        XCTAssertEqual(FieldEdit.recheck(key: "address", value: "", type: .nric), .missing)
    }

    // MARK: Document pass count

    func testFixingAFailedPassportNumberCountsAsPass() {
        XCTAssertEqual(FieldEdit.adjustedPassed(passed: 4, total: 5, key: "passportNumber", type: .passport,
                                                old: .ocr, new: .user), 5)
    }

    func testBreakingAChecksumDropsTheCount() {
        XCTAssertEqual(FieldEdit.adjustedPassed(passed: 2, total: 2, key: "nric", type: .nric,
                                                old: .nric, new: .ocr), 1)
    }

    func testUncheckedFieldsDoNotMoveTheCount() {
        XCTAssertEqual(FieldEdit.adjustedPassed(passed: 1, total: 2, key: "address", type: .nric,
                                                old: .ocr, new: .user), 1)
        XCTAssertEqual(FieldEdit.adjustedPassed(passed: 0, total: 0, key: "merchant", type: .receipt,
                                                old: .ocr, new: .user), 0)
    }

    func testCountStaysInRange() {
        XCTAssertEqual(FieldEdit.adjustedPassed(passed: 5, total: 5, key: "expiry", type: .passport,
                                                old: .ocr, new: .user), 5)
        XCTAssertEqual(FieldEdit.adjustedPassed(passed: 0, total: 1, key: "pan", type: .bankCard,
                                                old: .luhn, new: .ocr), 0)
    }

    func testCardNumberRewritesLast4AndBrand() {
        let d = FieldEdit.derived(key: "pan", value: "4111111111114417")
        XCTAssertEqual(d["last4"], "4417")
        XCTAssertEqual(d["brand"], CardCheck.validate("4111111111114417")?.brand.rawValue)
        XCTAssertTrue(FieldEdit.derived(key: "surname", value: "CHAI").isEmpty)
    }
}

final class DisplayTextTests: XCTestCase {
    func testCapitalisesEachSegment() {
        XCTAssertEqual(DisplayText.capitalisedSegments("summarise"), "Summarise")
        XCTAssertEqual(DisplayText.capitalisedSegments("Passport · 1 document · all checks pass"),
                       "Passport · 1 document · All checks pass")
        XCTAssertEqual(DisplayText.capitalisedSegments("- ~~Old~~ · Passport · Lee · deleted 2026-10-11 after 30 d"),
                       "- ~~Old~~ · Passport · Lee · Deleted 2026-10-11 after 30 d")
    }
    func testLeavesUnitsCodesAndChineseAlone() {
        XCTAssertEqual(DisplayText.capitalisedSegments("60 s in background"), "60 s in background")
        XCTAssertEqual(DisplayText.capitalisedSegments("English · 简体 · 繁體"), "English · 简体 · 繁體")
        XCTAssertEqual(DisplayText.capitalisedSegments("SG region"), "SG region")
    }
    func testDatesInsideALine() {
        XCTAssertEqual(DisplayText.displayDates(in: "Deleted 2026-10-11 after 30 d"), "Deleted 11/OCT/2026 after 30 d")
        XCTAssertEqual(DisplayText.displayDates(in: "no date here"), "no date here")
    }
}
