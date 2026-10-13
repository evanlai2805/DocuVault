import XCTest
@testable import DocuVaultCore

/// Checkpoint 16: the Vault's expiry warnings and the copy wordings on a vault item.
final class LibraryVaultTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Singapore")!
        return c
    }
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d))! }

    // MARK: Expiry

    func testPassportWarnsInsideSixMonths() {
        let now = day(2026, 10, 13)
        let s = DocumentExpiry.status(type: .passport, fields: ["expiry": "2027-04-02"], now: now, calendar: cal)
        XCTAssertEqual(s, .soon(daysLeft: 171))
        XCTAssertEqual(DocumentExpiry.phrase(s), "Expires in 5 months")
    }

    func testPassportOutsideSixMonthsIsQuiet() {
        let s = DocumentExpiry.status(type: .passport, fields: ["expiry": "2031-03-05"], now: day(2026, 10, 13), calendar: cal)
        XCTAssertEqual(s, DocumentExpiry.Status.none)
    }

    func testIDCardWarnsOnlyInsideOneMonth() {
        let now = day(2026, 10, 13)
        XCTAssertEqual(DocumentExpiry.status(type: .chinaID, fields: ["validTo": "2026-11-01"], now: now, calendar: cal), .soon(daysLeft: 19))
        XCTAssertEqual(DocumentExpiry.status(type: .chinaID, fields: ["validTo": "2026-12-01"], now: now, calendar: cal), DocumentExpiry.Status.none)
        XCTAssertEqual(DocumentExpiry.phrase(.soon(daysLeft: 19)), "Expires in 19 d")
    }

    func testLongTermChinaIDHasNoDate() {
        XCTAssertNil(DocumentExpiry.date(type: .chinaID, fields: ["validTo": "长期"], calendar: cal))
    }

    func testBankCardIsValidToTheEndOfItsMonth() {
        XCTAssertEqual(DocumentExpiry.date(type: .bankCard, fields: ["expiry": "10/26"], calendar: cal), day(2026, 10, 31))
        XCTAssertEqual(DocumentExpiry.status(type: .bankCard, fields: ["expiry": "10/26"], now: day(2026, 10, 13), calendar: cal), .soon(daysLeft: 18))
        XCTAssertEqual(DocumentExpiry.status(type: .bankCard, fields: ["expiry": "09/26"], now: day(2026, 10, 13), calendar: cal), .expired)
    }

    func testOtherTypesNeverWarn() {
        XCTAssertEqual(DocumentExpiry.status(type: .contract, fields: ["expiry": "2026-10-20"], now: day(2026, 10, 13), calendar: cal), DocumentExpiry.Status.none)
    }

    func testExpiresTodayAndExpired() {
        XCTAssertEqual(DocumentExpiry.phrase(.soon(daysLeft: 0)), "Expires today")
        XCTAssertEqual(DocumentExpiry.phrase(.expired), "Expired")
    }

    // MARK: Copy

    func testTapCopiesTheDisplayedDate() {
        XCTAssertEqual(CopyVariants.shown(fieldKey: "dateOfBirth", value: "1999-05-28", type: .passport), "28/MAY/1999")
        XCTAssertEqual(CopyVariants.shown(fieldKey: "expiry", value: "10/26", type: .bankCard), "10/26")
    }

    func testDateOptionsMatchTheKeyboardMenuWithoutTheTapValue() {
        let texts = CopyVariants.options(fieldKey: "dateOfBirth", value: "1999-05-28", type: .passport).map(\.text)
        XCTAssertEqual(texts, ["28/05/1999", "28-MAY-1999", "1999-05-28", "28051999"])
    }

    func testCardNumberOffersSpacedAndPlain() {
        let texts = CopyVariants.options(fieldKey: "pan", value: "4111111111111111", type: .bankCard).map(\.text)
        XCTAssertEqual(texts, ["4111 1111 1111 1111"])   // the plain number is what a tap copies
    }

    func testNationalityOffersWordingsMinusTheStoredOne() {
        let texts = CopyVariants.options(fieldKey: "nationality", value: "SGP", type: .passport).map(\.text)
        XCTAssertEqual(texts, ["Singaporean", "Singapore", "Singapore citizen"])
    }

    func testChineseNameOffersPinyin() {
        let texts = CopyVariants.options(fieldKey: "name", value: "柴思琳", type: .chinaID, fields: ["namePinyin": "CHAI SILIN"]).map(\.text)
        XCTAssertEqual(texts, ["CHAI SILIN"])
    }

    func testPlainFieldHasNoOptions() {
        XCTAssertTrue(CopyVariants.options(fieldKey: "surname", value: "LAI", type: .passport).isEmpty)
    }
}
