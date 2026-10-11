import XCTest
@testable import DocuVaultCore

/// Samples are the checkpoint-2 OCR texts. Every assertion here is a promise the review screen relies on.
final class ClassifierTests: XCTestCase {

    static let passport: [String] = [
        "REPUBLIC OF SINGAPORE  PASSPORT", "Type P   Code SGP   Passport No. K1234567A", "Surname TAN", "Given Names EVAN",
        "Nationality SINGAPORE CITIZEN", "Date of birth 12 APR 1999   Sex M", "Date of issue 01 MAR 2021", "Date of expiry 28 FEB 2031",
        MRZ.buildLine1(issuingCountry: "SGP", surname: "TAN", givenNames: "EVAN"),
        MRZ.buildLine2(documentNumber: "K1234567A", nationality: "SGP", dateOfBirth: "990412", sex: "M", expiry: "310228")
    ]
    static let nric: [String] = [
        "IDENTITY CARD NO. S9912345A", "Name TAN EVAN", "Race CHINESE   Sex M", "Date of birth 12-04-1999",
        "Country/Place of birth SINGAPORE", "(back) Blood Group B+   Date of issue 15-04-2014",
        "Address 123 BEDOK NORTH ST 1 #05-123 SINGAPORE 460123"
    ]
    static let chinaID: [String] = [
        "姓名 王伟", "性别 男   民族 汉", "出生 1985年6月15日", "住址 陕西省西安市雁塔区科技路10号",
        "公民身份号码 610113198506150012", "(背面) 签发机关 西安市公安局雁塔分局", "有效期限 2015.06.15-2035.06.15"
    ]
    static let card: [String] = ["DBS  altitude", "4111 1111 1111 1111", "VALID THRU 09/29", "TAN EVAN", "(back) CVV 123   Customer service 1800 111 1111"]
    static let receipt: [String] = [
        "SINGAPORE AIRLINES", "Booking ref 7XK2PQ", "SIN-XIY  01 NOV 2026", "Fare            SGD 380.00",
        "Taxes & fees    SGD  32.00", "Total           SGD 412.00", "Paid VISA ****4417   10 OCT 2026"
    ]
    static let contract: [String] = [
        "租赁合同", "甲方（出租方）：西安某某制造有限公司", "乙方（承租方）：李某某",
        "第一条 租赁标的 位于陕西省西安市雁塔区科技路10号的厂房", "第二条 租赁期限 自2026年1月1日起至2028年12月31日止。",
        "第三条 合同总价 人民币1,250,000元", "本合同适用中华人民共和国法律"
    ]
    static let businessCard: [String] = ["王伟", "总经理", "西安某某制造有限公司", "+86 138 0000 0000", "wang.wei@example.com", "www.example.com"]
    static let letter: [String] = ["Dear Mr Tan,", "Thank you for your letter of 1 October.", "Yours sincerely,", "J. Lee"]

    func testEachSampleClassifies() {
        XCTAssertEqual(Classifier.classify(lines: Self.passport).type, .passport)
        XCTAssertEqual(Classifier.classify(lines: Self.nric).type, .nric)
        XCTAssertEqual(Classifier.classify(lines: Self.chinaID).type, .chinaID)
        XCTAssertEqual(Classifier.classify(lines: Self.card).type, .bankCard)
        XCTAssertEqual(Classifier.classify(lines: Self.receipt).type, .receipt)
        XCTAssertEqual(Classifier.classify(lines: Self.contract).type, .contract)
        XCTAssertEqual(Classifier.classify(lines: Self.businessCard).type, .businessCard)
        XCTAssertEqual(Classifier.classify(lines: Self.letter).type, .letter)
    }

    func testPassportScoreAndReasons() {
        let v = Classifier.classify(lines: Self.passport)
        XCTAssertGreaterThanOrEqual(v.score, 90)
        XCTAssertTrue(v.reasons.contains { $0.text.contains("MRZ check digits all pass") })
        XCTAssertEqual(v.ranked.first?.0, .passport)
    }

    func testUnknownTextIsOther() {
        let v = Classifier.classify(lines: ["The quick brown fox", "jumps over the lazy dog"])
        XCTAssertEqual(v.type, .other)
        XCTAssertLessThan(v.score, Classifier.modelThreshold)
    }

    func testCorruptMRZStillPassportButLowerScore() {
        var lines = Self.passport
        lines[9] = String(lines[9].dropLast()) + "9"     // break the composite digit
        let v = Classifier.classify(lines: lines)
        XCTAssertEqual(v.type, .passport)
        XCTAssertLessThan(v.score, 90)
    }
}

final class ExtractorTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-11T00:00:00Z")!

    private func value(_ r: ExtractionResult, _ key: String) -> String? {
        r.fields.first { $0.key == key }.map(\.value)
    }
    private func check(_ r: ExtractionResult, _ key: String) -> FieldCheck? {
        r.fields.first { $0.key == key }?.check
    }

    func testPassport() {
        let r = PassportExtractor.extract(lines: ClassifierTests.passport, now: now)
        XCTAssertEqual(r.checksPassed, 5); XCTAssertEqual(r.checksTotal, 5)
        XCTAssertEqual(value(r, "surname"), "TAN"); XCTAssertEqual(check(r, "surname"), .mrz)
        XCTAssertEqual(value(r, "givenNames"), "EVAN")
        XCTAssertEqual(value(r, "passportNumber"), "K1234567A"); XCTAssertEqual(check(r, "passportNumber"), .mrz)
        XCTAssertEqual(value(r, "dateOfBirth"), "1999-04-12")
        XCTAssertEqual(value(r, "expiry"), "2031-02-28")
        XCTAssertEqual(value(r, "issueDate"), "2021-03-01"); XCTAssertEqual(check(r, "issueDate"), .regex)
        XCTAssertEqual(check(r, "placeOfIssue"), .missing)
        XCTAssertEqual(r.fields.first { $0.key == "placeOfBirth" }?.section, .secondary)
        XCTAssertTrue(r.warnings.isEmpty, r.warnings.joined(separator: " | "))
    }

    func testPassportVisualMismatchWarns() {
        var lines = ClassifierTests.passport
        lines[1] = "Type P   Code SGP   Passport No. K1234S67A"   // OCR misread 5 → S in the printed zone
        let r = PassportExtractor.extract(lines: lines, now: now)
        XCTAssertEqual(value(r, "passportNumber"), "K1234567A")   // MRZ wins
        XCTAssertTrue(r.warnings.contains { $0.contains("differs from MRZ") })
    }

    func testPassportExpiringSoonWarns() {
        var lines = ClassifierTests.passport
        lines[9] = MRZ.buildLine2(documentNumber: "K1234567A", nationality: "SGP", dateOfBirth: "990412", sex: "M", expiry: "270301")
        let r = PassportExtractor.extract(lines: lines, now: now)
        XCTAssertTrue(r.warnings.contains { $0.contains("Expires in") })
    }

    func testNRIC() {
        let r = NRICExtractor.extract(lines: ClassifierTests.nric)
        XCTAssertEqual(value(r, "nric"), "S9912345A"); XCTAssertEqual(check(r, "nric"), .nric)
        XCTAssertEqual(value(r, "name"), "TAN EVAN")
        XCTAssertEqual(value(r, "dateOfBirth"), "1999-04-12")
        XCTAssertEqual(value(r, "sex"), "M")
        XCTAssertEqual(value(r, "postalCode"), "460123")
        XCTAssertEqual(value(r, "issueDate"), "2014-04-15")
        XCTAssertEqual(value(r, "address"), "123 BEDOK NORTH ST 1 #05-123 SINGAPORE 460123")
        XCTAssertEqual(value(r, "race"), "CHINESE"); XCTAssertEqual(r.fields.first { $0.key == "race" }?.section, .secondary)
        XCTAssertEqual(value(r, "bloodGroup"), "B+"); XCTAssertEqual(r.fields.first { $0.key == "bloodGroup" }?.section, .secondary)
        XCTAssertEqual(r.checksPassed, 2); XCTAssertEqual(r.checksTotal, 2)
    }

    func testChinaID() {
        let r = ChinaIDExtractor.extract(lines: ClassifierTests.chinaID)
        XCTAssertEqual(value(r, "name"), "王伟")
        XCTAssertEqual(value(r, "idNumber"), "610113198506150012"); XCTAssertEqual(check(r, "idNumber"), .cnid)
        XCTAssertEqual(value(r, "dateOfBirth"), "1985-06-15"); XCTAssertEqual(check(r, "dateOfBirth"), .cnid)
        XCTAssertEqual(value(r, "sex"), "男 M")
        XCTAssertEqual(value(r, "address"), "陕西省西安市雁塔区科技路10号")
        XCTAssertEqual(value(r, "issuer"), "西安市公安局雁塔分局")
        XCTAssertEqual(value(r, "validFrom"), "2015-06-15"); XCTAssertEqual(value(r, "validTo"), "2035-06-15")
        XCTAssertEqual(value(r, "ethnicity"), "汉"); XCTAssertEqual(r.fields.first { $0.key == "ethnicity" }?.section, .secondary)
        XCTAssertEqual(check(r, "namePinyin"), .missing)
        XCTAssertEqual(r.checksPassed, 3); XCTAssertEqual(r.checksTotal, 3)
        XCTAssertTrue(r.warnings.isEmpty, r.warnings.joined(separator: " | "))
    }

    func testChinaIDLongTermValidity() {
        var lines = ClassifierTests.chinaID
        lines[6] = "有效期限 2015.06.15-长期"
        let r = ChinaIDExtractor.extract(lines: lines)
        XCTAssertEqual(value(r, "validTo"), "长期")
    }

    func testBankCard() {
        let r = BankCardExtractor.extract(lines: ClassifierTests.card, now: now)
        XCTAssertEqual(value(r, "pan"), "4111111111111111"); XCTAssertEqual(check(r, "pan"), .luhn)
        XCTAssertEqual(value(r, "brand"), "Visa")
        XCTAssertEqual(value(r, "last4"), "1111")
        XCTAssertEqual(value(r, "expiry"), "09/29")
        XCTAssertEqual(value(r, "nameOnCard"), "TAN EVAN")
        XCTAssertEqual(value(r, "issuer"), "DBS  altitude")
        XCTAssertEqual(value(r, "cvv"), "123"); XCTAssertEqual(r.fields.first { $0.key == "cvv" }?.section, .secondary)
        XCTAssertEqual(r.checksPassed, 2); XCTAssertEqual(r.checksTotal, 2)
    }

    func testReceipt() {
        let r = ReceiptExtractor.extract(lines: ClassifierTests.receipt)
        XCTAssertEqual(value(r, "merchant"), "SINGAPORE AIRLINES")
        XCTAssertEqual(value(r, "date"), "2026-10-10")
        XCTAssertEqual(value(r, "currency"), "SGD")
        XCTAssertEqual(value(r, "total"), "412.00"); XCTAssertEqual(check(r, "total"), .regex)   // lines summed to total
        XCTAssertEqual(value(r, "cardLast4"), "4417")
        XCTAssertEqual(value(r, "paymentMethod"), "Visa")
        XCTAssertEqual(value(r, "reference"), "7XK2PQ")
        XCTAssertEqual(value(r, "category"), "Travel")
        XCTAssertEqual(r.checksPassed, 1); XCTAssertEqual(r.checksTotal, 1)
        XCTAssertEqual(ReceiptExtractor.csvRow(r), "2026-10-10,SINGAPORE AIRLINES,Travel,SGD,412.00,32.00,4417,7XK2PQ")
    }

    func testReceiptLinesNotSummingIsUnverifiedNotFailed() {
        var lines = ClassifierTests.receipt
        lines[3] = "Fare            SGD 300.00"
        let r = ReceiptExtractor.extract(lines: lines)
        XCTAssertEqual(value(r, "total"), "412.00"); XCTAssertEqual(check(r, "total"), .ocr)
        XCTAssertEqual(r.checksTotal, 0)
    }

    func testContract() {
        let r = ContractExtractor.extract(lines: ClassifierTests.contract, type: .contract)
        XCTAssertEqual(value(r, "title"), "租赁合同")
        XCTAssertEqual(value(r, "partyA"), "西安某某制造有限公司")
        XCTAssertEqual(value(r, "partyB"), "李某某")
        XCTAssertEqual(value(r, "effectiveDate"), "2026-01-01")
        XCTAssertEqual(value(r, "expiryDate"), "2028-12-31")
        XCTAssertEqual(value(r, "amounts"), "CNY 1250000.00")
        XCTAssertEqual(value(r, "governingLaw"), "中华人民共和国法律")
    }

    func testBusinessCard() {
        let r = BusinessCardExtractor.extract(lines: ClassifierTests.businessCard)
        XCTAssertEqual(value(r, "name"), "王伟")
        XCTAssertEqual(value(r, "title"), "总经理")
        XCTAssertEqual(value(r, "company"), "西安某某制造有限公司")
        XCTAssertEqual(value(r, "email"), "wang.wei@example.com")
        XCTAssertEqual(value(r, "phone"), "+8613800000000")
        XCTAssertEqual(value(r, "website"), "www.example.com")
    }

    func testAllISODates() {
        let d = TextRules.allISODates(in: "From 2026年1月1日 to 31 Dec 2028, signed 10/10/2026 and again 2026-10-10.")
        XCTAssertEqual(d, ["2026-01-01", "2028-12-31", "2026-10-10", "2026-10-10"])
    }

    func testExtractorDispatch() {
        XCTAssertEqual(Extractor.extract(type: .passport, lines: ClassifierTests.passport).type, .passport)
        XCTAssertEqual(Extractor.extract(type: .other, lines: ["x"]).fields.count, 0)
        XCTAssertEqual(Extractor.extract(type: .letter, lines: ClassifierTests.letter).type, .letter)
    }
}
