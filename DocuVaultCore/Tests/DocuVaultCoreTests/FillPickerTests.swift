import XCTest
@testable import DocuVaultCore

/// The keyboard's picker: one flat list of every document and every person's shared fields,
/// most recently used first, searchable in English and Chinese.
final class FillPickerTests: XCTestCase {

    private let celine = UUID(), ben = UUID(), corinne = UUID()

    private func sample() -> [FillEntry] {
        [
            .init(title: "Passport · CHAI", personName: "Celine Chai", personID: celine, kind: .document(UUID())),
            .init(title: "DBS Altitude", personName: "Celine Chai", personID: celine, kind: .document(UUID())),
            .init(title: "Shared fields", personName: "Celine Chai", personID: celine, kind: .shared),
            .init(title: "Passport · ONG", personName: "Ben Ong", personID: ben, kind: .document(UUID())),
            .init(title: "身份证", personName: "Corinne Yap", personID: corinne, kind: .document(UUID())),
        ]
    }

    // MARK: Keys

    func testDocumentAndSharedKeysDoNotCollide() {
        let id = UUID()
        let doc = FillPicker.key(personID: celine, kind: .document(id))
        let shared = FillPicker.key(personID: celine, kind: .shared)
        XCTAssertNotEqual(doc, shared)
        XCTAssertTrue(doc.hasPrefix("doc:"))
        XCTAssertTrue(shared.hasPrefix("shared:"))
    }

    func testSharedKeyIsPerPerson() {
        XCTAssertNotEqual(FillPicker.key(personID: celine, kind: .shared),
                          FillPicker.key(personID: ben, kind: .shared))
    }

    // MARK: Ordering

    func testUnusedListKeepsIncomingOrder() {
        let e = sample()
        XCTAssertEqual(FillPicker.sorted(e, lastUsed: [:]).map(\.title), e.map(\.title))
    }

    func testMostRecentlyUsedComesFirst() {
        let e = sample()
        let now = Date()
        let lastUsed = [
            e[4].id: now,                        // 身份证, just used
            e[1].id: now.addingTimeInterval(-60) // DBS Altitude, a minute ago
        ]
        XCTAssertEqual(FillPicker.sorted(e, lastUsed: lastUsed).map(\.title),
                       ["身份证", "DBS Altitude", "Passport · CHAI", "Shared fields", "Passport · ONG"])
    }

    func testUsedRowsAlwaysOutrankUnusedOnes() {
        let e = sample()
        // Used a long time ago still beats never used at all.
        let lastUsed = [e[3].id: Date(timeIntervalSince1970: 0)]
        XCTAssertEqual(FillPicker.sorted(e, lastUsed: lastUsed).first?.title, "Passport · ONG")
    }

    func testIdenticalTimestampsKeepIncomingOrder() {
        let e = sample()
        let t = Date()
        let sorted = FillPicker.sorted(e, lastUsed: [e[2].id: t, e[0].id: t])
        XCTAssertEqual(sorted.prefix(2).map(\.title), ["Passport · CHAI", "Shared fields"])
    }

    // MARK: Search

    func testEmptyQueryReturnsEverything() {
        XCTAssertEqual(FillPicker.filter(sample(), query: "   ").count, 5)
    }

    func testMatchesTitleAndPerson() {
        XCTAssertEqual(FillPicker.filter(sample(), query: "passport").map(\.title),
                       ["Passport · CHAI", "Passport · ONG"])
        XCTAssertEqual(FillPicker.filter(sample(), query: "ben").map(\.title), ["Passport · ONG"])
    }

    func testMatchIgnoresCase() {
        XCTAssertEqual(FillPicker.filter(sample(), query: "DBS").count, 1)
        XCTAssertEqual(FillPicker.filter(sample(), query: "dbs").count, 1)
    }

    func testChineseTitleMatchesItsCharacters() {
        XCTAssertEqual(FillPicker.filter(sample(), query: "身份").map(\.title), ["身份证"])
    }

    func testChineseTitleMatchesPinyinTypedOnALatinKeyboard() {
        XCTAssertEqual(FillPicker.filter(sample(), query: "shen").map(\.title), ["身份证"])
        XCTAssertEqual(FillPicker.filter(sample(), query: "shenfen").map(\.title), ["身份证"])
    }

    func testNoMatchReturnsEmpty() {
        XCTAssertTrue(FillPicker.filter(sample(), query: "mortgage").isEmpty)
    }

    func testSharedFieldsIsFindableByName() {
        XCTAssertEqual(FillPicker.filter(sample(), query: "shared").map(\.title), ["Shared fields"])
    }

    // MARK: Person filter

    func testNilPersonKeepsEveryone() {
        XCTAssertEqual(FillPicker.filter(sample(), person: nil).count, 5)
    }

    func testPersonFilterKeepsOnlyThatPerson() {
        let rows = FillPicker.filter(sample(), person: celine)
        XCTAssertEqual(rows.count, 3)
        XCTAssertTrue(rows.allSatisfy { $0.personName == "Celine Chai" })
        XCTAssertTrue(rows.contains { $0.kind == .shared }, "shared fields stay with their person")
    }

    func testPersonFilterComposesWithSearch() {
        let byPerson = FillPicker.filter(sample(), person: celine)
        XCTAssertEqual(FillPicker.filter(byPerson, query: "passport").map(\.title), ["Passport · CHAI"])
    }

    func testUnknownPersonYieldsNothing() {
        XCTAssertTrue(FillPicker.filter(sample(), person: UUID()).isEmpty)
    }

    // MARK: Romanisation

    func testRomanisedDropsPunctuationAndSpaces() {
        XCTAssertEqual(FillPicker.romanised("Passport · CHAI"), "PASSPORTCHAI")
    }

    func testRomanisedConvertsChinese() {
        XCTAssertEqual(FillPicker.romanised("身份证"), "SHENFENZHENG")
    }
}
