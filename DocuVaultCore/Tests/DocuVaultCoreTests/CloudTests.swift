import XCTest
@testable import DocuVaultCore

final class RedactorTests: XCTestCase {

    let letter = """
    Dear Mr Tan Ah Kow,

    We refer to the engagement dated 3 October 2026. Our client, Lee & Co Pte Ltd, requests two more weeks.
    The fee of SGD 18,000 is adjusted by S$1,500 for the delay. Please confirm by 17 October 2026.
    Our reference S1234567D; card 4111 1111 1111 1111; contact +65 9123 4567 or jlee@leeco.sg.
    Yours faithfully,
    Signed by: Jasmine Lee
    """

    func testFindsEveryCategory() {
        let spans = Redactor.findSpans(in: letter)
        let by = Dictionary(grouping: spans, by: \.category).mapValues { $0.map(\.original) }
        XCTAssertEqual(Set(by[.name] ?? []), ["Tan Ah Kow", "Lee & Co Pte Ltd", "Jasmine Lee"])
        XCTAssertEqual(by[.amount], ["SGD 18,000", "S$1,500"])
        XCTAssertEqual(Set(by[.identifier] ?? []), ["S1234567D", "4111 1111 1111 1111"])
        XCTAssertEqual(Set(by[.contact] ?? []), ["+65 9123 4567", "jlee@leeco.sg"])
        XCTAssertEqual(by[.date]?.count, 2)
        // Non-overlapping and sorted.
        for (a, b) in zip(spans, spans.dropFirst()) { XCTAssertLessThanOrEqual(a.location + a.length, b.location) }
    }

    func testApplyRespectsOptionsAndLocks() {
        let spans = Redactor.findSpans(in: letter)
        let r = Redactor.apply(letter, spans: spans, options: Redactor.Options(names: false, amounts: false, dates: false))
        XCTAssertTrue(r.text.contains("Tan Ah Kow"))                   // names kept
        XCTAssertTrue(r.text.contains("SGD 18,000"))                   // amounts kept
        XCTAssertFalse(r.text.contains("S1234567D"))                   // identifiers always go
        XCTAssertFalse(r.text.contains("4111 1111"))
        XCTAssertFalse(r.text.contains("jlee@leeco.sg"))
        XCTAssertTrue(r.text.contains("[ID 1]") && r.text.contains("[ID 2]"))
        XCTAssertTrue(r.text.contains("[CONTACT 1]") && r.text.contains("[CONTACT 2]"))
        XCTAssertEqual(r.counts[.identifier], 2)
        XCTAssertEqual(r.counts[.contact], 2)
        XCTAssertNil(r.counts[.name])
    }

    func testPlaceholdersAreStableAndCarryCurrency() {
        let text = "Party A: Alpha Beta Pte Ltd pays SGD 100. Alpha Beta Pte Ltd then pays SGD 100 again and CNY 5,000."
        let r = Redactor.apply(text, spans: Redactor.findSpans(in: text))
        XCTAssertEqual(r.text.components(separatedBy: "[NAME 1]").count - 1, 2)      // same company → same index
        XCTAssertEqual(r.text.components(separatedBy: "[AMOUNT 1 SGD]").count - 1, 2) // same amount → same index
        XCTAssertTrue(r.text.contains("[AMOUNT 2 CNY]"))
        XCTAssertEqual(r.map["[NAME 1]"], "Alpha Beta Pte Ltd")
        XCTAssertEqual(r.map["[AMOUNT 2 CNY]"], "CNY 5,000")
    }

    func testRestoreRoundTrip() {
        let spans = Redactor.findSpans(in: letter)
        let r = Redactor.apply(letter, spans: spans)
        let reply = "[NAME 2] asks for two weeks. Fee [AMOUNT 1 SGD] less [AMOUNT 2]. Contact [CONTACT 1]. Also [NAME 9] is unknown."
        let (text, unresolved) = Redactor.restore(reply, map: r.map)
        XCTAssertTrue(text.contains("Lee & Co Pte Ltd asks for two weeks"))
        XCTAssertTrue(text.contains("Fee SGD 18,000 less S$1,500"))     // bare [AMOUNT 2] resolves without the currency tag
        XCTAssertTrue(text.contains("Contact +65 9123 4567"))
        XCTAssertTrue(text.contains("[NAME 9]"))
        XCTAssertEqual(unresolved, 1)

        var s = DocumentSummary(language: "en", headline: "[NAME 2] extension", format: .bullets,
                                body: ["Fee [AMOUNT 1 SGD]."], keyFacts: [.init(label: "From", value: "[NAME 3]")], actions: ["Reply to [CONTACT 2]"])
        let restored = Redactor.restore(s, map: r.map)
        XCTAssertEqual(restored.summary.headline, "Lee & Co Pte Ltd extension")
        XCTAssertEqual(restored.summary.body, ["Fee SGD 18,000."])
        XCTAssertEqual(restored.summary.keyFacts.first?.value, "Jasmine Lee")
        XCTAssertEqual(restored.summary.actions, ["Reply to jlee@leeco.sg"])
        XCTAssertEqual(restored.unresolved, 0)
        s.model = "claude"
        XCTAssertEqual(s.model, "claude")
    }

    func testChineseNamesCompaniesAndIDs() {
        let contract = """
        厂房租赁合同
        甲方：西安某某制造有限公司（出租方）
        乙方：李某某，身份证号 11010519491231002X，电话 13800138000
        丙方 王小明先生 作为担保人。联系人：张伟（电话 029-87654321）
        租金人民币1,250,000元，自2026年1月1日起。
        """
        let spans = Redactor.findSpans(in: contract)
        let by = Dictionary(grouping: spans, by: \.category).mapValues { Set($0.map(\.original)) }
        XCTAssertTrue(by[.name]?.contains("西安某某制造有限公司") == true, "\(by[.name] ?? [])")
        XCTAssertTrue(by[.name]?.contains("李某某") == true, "\(by[.name] ?? [])")
        XCTAssertTrue(by[.name]?.contains("王小明") == true, "\(by[.name] ?? [])")
        XCTAssertTrue(by[.name]?.contains("张伟") == true, "\(by[.name] ?? [])")
        XCTAssertFalse(by[.name]?.contains("甲方西安某某制造有限公司") == true)
        XCTAssertEqual(by[.identifier], ["11010519491231002X"])
        XCTAssertEqual(by[.contact], ["13800138000", "029-87654321"])
        XCTAssertEqual(by[.amount]?.count, 1)
        let r = Redactor.apply(contract, spans: spans)
        XCTAssertFalse(r.text.contains("李某某"))
        XCTAssertTrue(r.text.contains("[AMOUNT 1 CNY]"))
        XCTAssertTrue(r.text.contains("2026年1月1日"))        // dates off by default
    }

    func testKnownNamesAndNoFalseDates() {
        let text = "Minutes: Evan Lai presented. The period 2026-2028 covers three years. Contact Evan."
        let spans = Redactor.findSpans(in: text, extraNames: ["Evan Lai", "Lai"])
        let names = spans.filter { $0.category == .name }.map(\.original)
        XCTAssertEqual(names, ["Evan Lai"])                      // longest known name wins; "Lai" inside it is not double-counted
        XCTAssertTrue(spans.filter { $0.category == .contact }.isEmpty, "2026-2028 is not a phone number")
    }

    func testNoFalseCardNumbersWithoutLuhn() {
        let text = "Invoice 1234 5678 9012 3456 total SGD 12."       // fails Luhn
        XCTAssertTrue(Redactor.findSpans(in: text).filter { $0.category == .identifier }.isEmpty)
        let ok = "Card 4242 4242 4242 4242"                           // passes Luhn
        XCTAssertEqual(Redactor.findSpans(in: ok).filter { $0.category == .identifier }.count, 1)
    }

    func testMRZLineIsRedactedWhole() {
        let text = "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<\nL898902C36UTO7408122F1204159ZE184226B<<<<<10"
        let ids = Redactor.findSpans(in: text).filter { $0.category == .identifier }
        XCTAssertEqual(ids.count, 2)
    }
}

final class CloudGateTests: XCTestCase {

    func testGateIsCodeNotPrompt() {
        XCTAssertTrue(CloudGate.allows(type: .contract, sensitive: false, hasSealedContent: false))
        XCTAssertTrue(CloudGate.allows(type: .letter, sensitive: false, hasSealedContent: false))
        XCTAssertTrue(CloudGate.allows(type: .other, sensitive: false, hasSealedContent: false))
        XCTAssertFalse(CloudGate.allows(type: .contract, sensitive: true, hasSealedContent: false))
        XCTAssertFalse(CloudGate.allows(type: .contract, sensitive: false, hasSealedContent: true))
        for t in [DocumentType.passport, .nric, .chinaID, .bankCard, .receipt, .businessCard] {
            XCTAssertFalse(CloudGate.allows(type: t, sensitive: false, hasSealedContent: false), "\(t)")
        }
        XCTAssertEqual(CloudGate.reason(type: .passport, sensitive: true), "Vault documents never leave this phone.")
    }

    func testCostEstimate() {
        let en = String(repeating: "word ", count: 400)              // 2000 chars → ~500 tokens
        XCTAssertEqual(CloudCost.estimatedTokens(for: en), 500)
        let zh = String(repeating: "租", count: 1000)                 // 1000 CJK → 1300 tokens
        XCTAssertEqual(CloudCost.estimatedTokens(for: zh), 1300)
        let usd = CloudCost.estimateUSD(inputTokens: 1000, outputTokens: 500, model: "claude-sonnet-5-5")
        XCTAssertEqual(usd, 0.003 + 0.0075, accuracy: 1e-9)
        XCTAssertEqual(CloudCost.formatUSD(0.001), "< US$0.01")
        XCTAssertEqual(CloudCost.formatUSD(0.0105), "US$0.01")
        XCTAssertEqual(CloudCost.model("nope").id, CloudCost.defaultModelID)
    }

    func testPurposeLabels() {
        XCTAssertEqual(CloudPurpose.summarise(format: .bullets, length: .short, language: "en").logLabel, "summarise")
        XCTAssertEqual(CloudPurpose.ask(question: "违约金条款？", language: "zh-Hans").logLabel, "ask: \u{201C}违约金条款？\u{201D}")
        let long = String(repeating: "x", count: 60)
        XCTAssertTrue(CloudPurpose.ask(question: long, language: "en").logLabel.contains("…"))
    }
}
