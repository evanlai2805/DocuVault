import XCTest
@testable import DocuVaultCore

final class SummarySpecTests: XCTestCase {

    func testLanguageAndFormatDefaults() {
        XCTAssertEqual(SummarySpec.language(for: "甲方：西安某某制造有限公司 乙方：李某某 租赁合同"), "zh-Hans")
        XCTAssertEqual(SummarySpec.language(for: "Dear Mr Tan, thank you for your letter."), "en")
        XCTAssertTrue(SummarySpec.isMixed("Lease Agreement 租赁合同 between Party A 甲方 and Party B 乙方 for premises"))
        XCTAssertEqual(SummarySpec.defaultFormat(for: .contract), .bullets)
        XCTAssertEqual(SummarySpec.defaultFormat(for: .letter), .paragraph)
        XCTAssertEqual(SummarySpec.defaultFormat(for: .other), .unsure)
        XCTAssertFalse(SummarySpec.supportsSummary(.receipt))
        XCTAssertFalse(SummarySpec.supportsSummary(.passport))
        XCTAssertTrue(SummarySpec.supportsSummary(.contract))
    }

    func testInstructionsFollowLanguage() {
        let en = SummarySpec.instructions(language: "en", format: .bullets, length: .short)
        XCTAssertTrue(en.contains("under 20 words"))
        XCTAssertTrue(en.contains("Do not guess"))
        XCTAssertTrue(en.contains("3 to 5 bullets"))
        let zh = SummarySpec.instructions(language: "zh-Hans", format: .paragraph, length: .long)
        XCTAssertTrue(zh.contains("简体中文"))
        XCTAssertFalse(zh.contains("20 words"))          // STE is not applied to Chinese
        XCTAssertTrue(zh.contains("一段话"))
    }

    func testChunkingRespectsClausesAndTables() {
        let clauses = (1...30).map { "第\($0)条 " + String(repeating: "本条款内容。", count: 20) }   // ~130 chars each
        let text = clauses.joined(separator: "\n")
        let chunks = SummarySpec.chunks(text, language: "zh-Hans")
        XCTAssertGreaterThan(chunks.count, 1)
        for c in chunks {
            XCTAssertLessThanOrEqual(c.count, SummarySpec.chunkLimit(language: "zh-Hans"))
            XCTAssertTrue(c.hasPrefix("第"), "chunk must start at a clause boundary: \(c.prefix(10))")
        }
        // Reassembled text loses nothing.
        XCTAssertEqual(chunks.joined(separator: "\n").count, text.count)

        let table = "| A | B |\n| 1 | 2 |\n1. next clause"
        let paras = SummarySpec.paragraphize(table)
        XCTAssertEqual(paras.count, 1, "a numbered line directly after a table row stays with the table")
    }

    func testShortTextIsOneChunk() {
        XCTAssertEqual(SummarySpec.chunks("Dear Sir,\n\nShort letter.", language: "en").count, 1)
    }

    func testOversizedParagraphHardSplits() {
        let long = String(repeating: "This is a sentence. ", count: 400)   // ~8000 chars, no newlines
        let chunks = SummarySpec.chunks(long, language: "en")
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= SummarySpec.chunkLimit(language: "en") })
    }

    func testGroundingDropsInventedFacts() {
        let source = "合同总价 人民币1,250,000元。租期自2026年1月1日起至2028年12月31日止。适用中华人民共和国法律。"
        let facts = [
            DocumentSummary.Fact(label: "金额", value: "人民币1,250,000元"),
            DocumentSummary.Fact(label: "金额", value: "1250000"),              // commas removed still matches
            DocumentSummary.Fact(label: "期限", value: "2026-01-01"),            // date in another format matches
            DocumentSummary.Fact(label: "法律", value: "新加坡法律"),             // invented
            DocumentSummary.Fact(label: "押金", value: "人民币100,000元"),         // invented
        ]
        let g = SummarySpec.grounded(facts, in: source)
        XCTAssertEqual(g.map(\.value), ["人民币1,250,000元", "1250000", "2026-01-01"])
    }

    func testMergeFacts() {
        let a = [DocumentSummary.Fact(label: "Party A", value: "Lee & Co")]
        let b = [DocumentSummary.Fact(label: "party a", value: "LEE & CO"), DocumentSummary.Fact(label: "Deadline", value: "2026-11-07")]
        XCTAssertEqual(SummarySpec.mergeFacts([a, b]).count, 2)
    }

    func testMarkdownRendering() {
        let s = DocumentSummary(language: "en", headline: "Request to extend", format: .paragraph,
                                body: ["Lee & Co asks for two more weeks.", "They want the draft by 7 November."],
                                keyFacts: [.init(label: "Deadline", value: "2026-11-07")], actions: ["Confirm by Fri 17 Oct"])
        let md = s.markdown
        XCTAssertTrue(md.contains("**Request to extend**"))
        XCTAssertTrue(md.contains("Lee & Co asks for two more weeks. They want the draft by 7 November."))
        XCTAssertTrue(md.contains("### Key facts\n- Deadline: 2026-11-07"))
        XCTAssertTrue(md.contains("- [ ] Confirm by Fri 17 Oct"))
        var zh = s; zh.language = "zh-Hans"; zh.format = .bullets
        XCTAssertTrue(zh.markdown.contains("### 要点"))
        XCTAssertTrue(zh.markdown.contains("- Lee & Co asks"))
    }

    func testPrompts() {
        XCTAssertTrue(SummarySpec.prompt(text: "x", language: "en", chunk: (2, 6)).contains("part 3 of 6"))
        XCTAssertTrue(SummarySpec.prompt(text: "x", language: "zh-Hans").contains("<document>"))
        let partials = [DocumentSummary(language: "en", headline: "A", format: .bullets, body: ["one"], keyFacts: [], actions: []),
                        DocumentSummary(language: "en", headline: "B", format: .bullets, body: ["two"], keyFacts: [.init(label: "k", value: "v")], actions: [])]
        let r = SummarySpec.reducePrompt(partials: partials, language: "en")
        XCTAssertTrue(r.contains("Part 2: B"))
        XCTAssertTrue(r.contains("Facts: k=v"))
    }
}

final class SummaryJSONTests: XCTestCase {
    func testCleanJSON() {
        let reply = #"{"headline":"厂房租赁合同","format":"bullets","body":["租期三年。","总价125万元。"],"keyFacts":[{"label":"金额","value":"人民币1,250,000元"}],"actions":["核对付款日期"]}"#
        let s = SummaryJSON.parse(reply, language: "zh-Hans")!
        XCTAssertEqual(s.headline, "厂房租赁合同")
        XCTAssertEqual(s.format, .bullets)
        XCTAssertEqual(s.body.count, 2)
        XCTAssertEqual(s.keyFacts.first?.value, "人民币1,250,000元")
        XCTAssertEqual(s.actions, ["核对付款日期"])
        XCTAssertEqual(s.model, "mlx")
    }
    func testFencesThinkingAndChatter() {
        let reply = """
        <think>let me read the document…</think>
        Sure, here is the summary:
        ```json
        {"headline": "Request to extend", "format": "paragraph", "body": ["They ask for two weeks."], "key_facts": [{"key": "Deadline", "value": "2026-11-07"}], "actions": []}
        ```
        Let me know if you need more.
        """
        let s = SummaryJSON.parse(reply, language: "en")!
        XCTAssertEqual(s.headline, "Request to extend")
        XCTAssertEqual(s.format, .paragraph)
        XCTAssertEqual(s.keyFacts, [.init(label: "Deadline", value: "2026-11-07")])
    }
    func testBracesInsideStringsDoNotBreakExtraction() {
        let reply = #"{"headline":"Clause {3} applies","format":"bullets","body":["Text with } brace"],"keyFacts":[],"actions":[]}"#
        XCTAssertEqual(SummaryJSON.parse(reply, language: "en")?.headline, "Clause {3} applies")
    }
    func testBodyAsStringIsSplit() {
        let reply = #"{"headline":"H","format":"list","body":"- one\n- two\n• three","keyFacts":[],"actions":[]}"#
        let s = SummaryJSON.parse(reply, language: "en")!
        XCTAssertEqual(s.body, ["one", "two", "three"])
        XCTAssertEqual(s.format, .bullets)
    }
    func testGarbageReturnsNil() {
        XCTAssertNil(SummaryJSON.parse("I cannot do that.", language: "en"))
        XCTAssertNil(SummaryJSON.parse("{\"unrelated\": 1}", language: "en"))
    }
}
