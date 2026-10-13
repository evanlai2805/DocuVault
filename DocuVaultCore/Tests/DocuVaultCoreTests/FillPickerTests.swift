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

    // MARK: Ranked search (keyboard rebuild, 13 Oct)

    func testSingleLetterMatchesWordStartsOnly() {
        // "g" used to find Ben Ong because "Ong" contains a g.
        XCTAssertTrue(FillPicker.search(sample(), query: "g").isEmpty)
        XCTAssertEqual(FillPicker.search(sample(), query: "o").map(\.entry.title), ["Passport · ONG"])
    }

    func testTitleStartRanksBeforeLaterWords() {
        let a = FillEntry(title: "Passport · CHAI", personName: "Celine Chai", personID: celine, kind: .document(UUID()))
        let b = FillEntry(title: "Contact details", personName: "Ben Ong", personID: ben, kind: .shared)
        // a is more recent, but b's title starts with the letter.
        XCTAssertEqual(FillPicker.search([a, b], query: "c").map(\.entry.title), ["Contact details", "Passport · CHAI"])
    }

    func testNameStartRanksBeforeOtherWords() {
        let a = FillEntry(title: "Bank Card", personName: "Celine Chai", personID: celine, kind: .document(UUID()))
        let b = FillEntry(title: "Lease", personName: "Ben Ong", personID: ben, kind: .document(UUID()))
        XCTAssertEqual(FillPicker.search([a, b], query: "b").map(\.entry.title), ["Bank Card", "Lease"])
        XCTAssertEqual(FillPicker.search([b, a], query: "ben").map(\.entry.title), ["Lease"])
    }

    func testInsideWordNeedsThreeLetters() {
        XCTAssertTrue(FillPicker.search(sample(), query: "or").isEmpty)
        XCTAssertEqual(FillPicker.search(sample(), query: "port").map(\.entry.title), ["Passport · CHAI", "Passport · ONG"])
    }

    func testInsideWordRanksAfterWordStarts() {
        let a = FillEntry(title: "Passport", personName: "Ann Lee", personID: celine, kind: .document(UUID()))
        let b = FillEntry(title: "Port permit", personName: "Ann Lee", personID: celine, kind: .document(UUID()))
        XCTAssertEqual(FillPicker.search([a, b], query: "port").map(\.entry.title), ["Port permit", "Passport"])
    }

    func testEveryQueryWordMustMatch() {
        XCTAssertEqual(FillPicker.search(sample(), query: "pass ben").map(\.entry.title), ["Passport · ONG"])
        XCTAssertEqual(FillPicker.search(sample(), query: "pass ce").map(\.entry.title), ["Passport · CHAI"])
    }

    func testHighlightsTheMatchedLetters() {
        let m = FillPicker.search(sample(), query: "pass ce").first
        XCTAssertEqual(m?.titleHighlight, [0..<4])
        XCTAssertEqual(m?.personHighlight, [0..<2])
        XCTAssertEqual(FillPicker.search(sample(), query: "chai").first?.titleHighlight, [11..<15])
    }

    func testPinyinMatchesFromAnyCharacterAndHighlightsIt() {
        XCTAssertEqual(FillPicker.search(sample(), query: "fenz").map(\.entry.title), ["身份证"])
        XCTAssertEqual(FillPicker.search(sample(), query: "shenf").first?.titleHighlight, [0..<2])
        XCTAssertEqual(FillPicker.search(sample(), query: "she").first?.titleHighlight, [0..<1])
    }

    // MARK: Keyboard titles

    func testIdentityDocumentsAreNamedByType() {
        XCTAssertEqual(FillPicker.entryTitle(stored: "REPUBLIC OF SINGAPORE", type: .passport), "Passport")
        XCTAssertEqual(FillPicker.entryTitle(stored: "Passport · CHAI", type: .passport), "Passport · CHAI")
        XCTAssertEqual(FillPicker.entryTitle(stored: "MINISTRY OF HOME AFFAIRS", type: .nric), "NRIC / FIN")
        XCTAssertEqual(FillPicker.entryTitle(stored: "居民身份证", type: .chinaID), "居民身份证")
        XCTAssertEqual(FillPicker.entryTitle(stored: "DBS Altitude", type: .bankCard), "DBS Altitude")
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

    // MARK: Start page

    func testStartPageSplitsMostUsedAndRecent() {
        let e = sample()
        let now = Date()
        let page = FillPicker.startPage(e,
            useCounts: [e[1].id: 9, e[3].id: 4, e[0].id: 1],
            lastUsed: [e[0].id: now, e[4].id: now.addingTimeInterval(-60), e[1].id: now.addingTimeInterval(-5)])
        XCTAssertEqual(page.mostUsed.map(\.title), ["DBS Altitude", "Passport · ONG"])
        XCTAssertEqual(page.recent.map(\.title), ["Passport · CHAI", "身份证"])
    }

    func testStartPageNeverRepeatsARow() {
        let e = sample()
        let now = Date()
        let page = FillPicker.startPage(e, useCounts: [e[0].id: 5, e[1].id: 3], lastUsed: [e[0].id: now, e[1].id: now.addingTimeInterval(-1), e[2].id: now.addingTimeInterval(-2)])
        XCTAssertEqual(page.mostUsed.map(\.id), [e[0].id, e[1].id])
        XCTAssertEqual(page.recent.map(\.id), [e[2].id, e[3].id])
        XCTAssertEqual(Set(page.mostUsed.map(\.id)).intersection(page.recent.map(\.id)), [])
    }

    func testStartPageWithNothingUsedFallsBackToIncomingOrder() {
        let e = sample()
        let page = FillPicker.startPage(e, useCounts: [:], lastUsed: [:])
        XCTAssertTrue(page.mostUsed.isEmpty)
        XCTAssertEqual(page.recent.map(\.id), [e[0].id, e[1].id])
    }

    func testStartPageTiesOnCountKeepIncomingOrder() {
        let e = sample()
        let page = FillPicker.startPage(e, useCounts: [e[3].id: 2, e[1].id: 2, e[0].id: 2], lastUsed: [:])
        XCTAssertEqual(page.mostUsed.map(\.id), [e[0].id, e[1].id])
    }
}
