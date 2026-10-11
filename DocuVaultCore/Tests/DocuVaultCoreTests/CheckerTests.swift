import XCTest
@testable import DocuVaultCore

final class MRZTests: XCTestCase {

    // ICAO 9303 Part 4 specimen (Utopia). The canonical public test vector.
    let icaoL1 = "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<"
    let icaoL2 = "L898902C36UTO7408122F1204159ZE184226B<<<<<10"

    func testICAOSpecimenParses() throws {
        let td3 = try MRZ.parseTD3(line1: icaoL1, line2: icaoL2)
        XCTAssertEqual(td3.issuingCountry, "UTO")
        XCTAssertEqual(td3.surname, "ERIKSSON")
        XCTAssertEqual(td3.givenNames, "ANNA MARIA")
        XCTAssertEqual(td3.documentNumber, "L898902C3")
        XCTAssertEqual(td3.nationality, "UTO")
        XCTAssertEqual(td3.dateOfBirth, "740812")
        XCTAssertEqual(td3.sex, "F")
        XCTAssertEqual(td3.expiryDate, "120415")
        XCTAssertEqual(td3.optionalData, "ZE184226B")
        XCTAssertTrue(td3.documentNumberCheckOK)
        XCTAssertTrue(td3.dateOfBirthCheckOK)
        XCTAssertTrue(td3.expiryCheckOK)
        XCTAssertTrue(td3.optionalDataCheckOK)
        XCTAssertTrue(td3.compositeCheckOK)
        XCTAssertTrue(td3.allChecksOK)
    }

    func testBuilderReproducesICAOSpecimen() {
        XCTAssertEqual(MRZ.buildLine1(issuingCountry: "UTO", surname: "ERIKSSON", givenNames: "ANNA MARIA"), icaoL1)
        XCTAssertEqual(MRZ.buildLine2(documentNumber: "L898902C3", nationality: "UTO", dateOfBirth: "740812",
                                      sex: "F", expiry: "120415", optionalData: "ZE184226B"), icaoL2)
    }

    func testSingaporeSampleRoundTrip() throws {
        let l1 = MRZ.buildLine1(issuingCountry: "SGP", surname: "TAN", givenNames: "EVAN")
        let l2 = MRZ.buildLine2(documentNumber: "K1234567A", nationality: "SGP", dateOfBirth: "990412", sex: "M", expiry: "310228")
        XCTAssertEqual(l1, "P<SGPTAN<<EVAN<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<")
        XCTAssertEqual(l2, "K1234567A6SGP9904123M3102282<<<<<<<<<<<<<<02")
        let td3 = try MRZ.parseTD3(line1: l1, line2: l2)
        XCTAssertTrue(td3.allChecksOK)
        XCTAssertEqual(td3.documentNumber, "K1234567A")
        let now = ISO8601DateFormatter().date(from: "2026-10-11T00:00:00Z")!
        XCTAssertEqual(td3.isoDateOfBirth(now: now), "1999-04-12")
        XCTAssertEqual(td3.isoExpiryDate(now: now), "2031-02-28")
    }

    func testCheckDigits() {
        XCTAssertEqual(MRZ.checkDigit("K1234567A"), 6)
        XCTAssertEqual(MRZ.checkDigit("990412"), 3)
        XCTAssertEqual(MRZ.checkDigit("310228"), 2)
        XCTAssertEqual(MRZ.checkDigit("L898902C3"), 6)
    }

    func testSingleDigitCorruptionIsCaught() throws {
        var chars = Array(icaoL2)
        chars[3] = "0"   // L898902C3 → L890902C3
        let td3 = try MRZ.parseTD3(line1: icaoL1, line2: String(chars))
        XCTAssertFalse(td3.documentNumberCheckOK)
        XCTAssertFalse(td3.compositeCheckOK)
        XCTAssertFalse(td3.allChecksOK)
    }

    func testLocateLinesInNoisyOCR() {
        let ocr = ["REPUBLIC OF SINGAPORE", "Passport No. K1234567A", "Surname TAN",
                   "p<sgptan<<evan<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<",
                   "K1234567A6SGP9904123M3102282<<<<<<<<<<<<<<02"]
        let found = MRZ.locateLines(in: ocr)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.0, "P<SGPTAN<<EVAN<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<")
    }

    func testWrongLengthThrows() {
        XCTAssertThrowsError(try MRZ.parseTD3(line1: "P<SGP", line2: icaoL2))
    }

    func testDOBCenturyRule() {
        let now = ISO8601DateFormatter().date(from: "2026-10-11T00:00:00Z")!
        XCTAssertEqual(MRZ.isoDate("740812", isExpiry: false, now: now), "1974-08-12")
        XCTAssertEqual(MRZ.isoDate("050101", isExpiry: false, now: now), "2005-01-01")
        XCTAssertEqual(MRZ.isoDate("260101", isExpiry: false, now: now), "2026-01-01")
        XCTAssertEqual(MRZ.isoDate("270101", isExpiry: false, now: now), "1927-01-01")
    }
}

final class CardCheckTests: XCTestCase {

    func testKnownValidNumbers() {
        // Standard public test numbers per brand.
        let cases: [(String, CardCheck.Brand)] = [
            ("4111 1111 1111 1111", .visa),
            ("5555 5555 5555 4444", .mastercard),
            ("2223 0031 2200 3222", .mastercard),
            ("3782 822463 10005", .amex),
            ("6200 0000 0000 0005", .unionPay),
            ("3530 1113 3330 0000", .jcb),
            ("6011 1111 1111 1117", .discover),
        ]
        for (n, brand) in cases {
            let r = CardCheck.validate(n)
            XCTAssertNotNil(r, n)
            XCTAssertTrue(r!.luhnOK, n)
            XCTAssertEqual(r!.brand, brand, n)
        }
    }

    func testSingleDigitErrorFailsLuhn() {
        XCTAssertFalse(CardCheck.validate("4111 1111 1111 1112")!.luhnOK)
    }

    func testTranspositionFailsLuhn() {
        // 4111111111111111 → swap positions 0 and 1 is identity; use a different valid number.
        XCTAssertTrue(CardCheck.luhn("5555555555554444"))
        XCTAssertFalse(CardCheck.luhn("5555555555544444"))
    }

    func testMaskedAndLast4() {
        let r = CardCheck.validate("4111111111114417")!
        XCTAssertEqual(r.last4, "4417")
        XCTAssertEqual(r.masked, "•••• •••• •••• 4417")
        let amex = CardCheck.validate("378282246310005")!
        XCTAssertEqual(amex.masked, "•••• •••••• 0005")
    }

    func testFindInOCRLinesPrefersLuhnValid() {
        let ocr = ["DBS altitude", "Customer service 1800 111 1111 ext 12345", "4111 1111 1111 1111", "VALID THRU 09/29"]
        let r = CardCheck.findCardNumber(in: ocr)
        XCTAssertEqual(r?.digits, "4111111111111111")
        XCTAssertTrue(r!.luhnOK)
    }

    func testExpiryParsing() {
        let e = CardCheck.parseExpiry("VALID THRU 09/29")
        XCTAssertEqual(e?.month, 9)
        XCTAssertEqual(e?.year, 2029)
        XCTAssertEqual(CardCheck.parseExpiry("EXP 12-2031")?.year, 2031)
        XCTAssertNil(CardCheck.parseExpiry("13/29"))
        let now = ISO8601DateFormatter().date(from: "2026-10-11T00:00:00Z")!
        XCTAssertTrue(CardCheck.expiryIsCurrentOrFuture(month: 10, year: 2026, now: now))
        XCTAssertFalse(CardCheck.expiryIsCurrentOrFuture(month: 9, year: 2026, now: now))
    }
}

final class NRICTests: XCTestCase {

    // Fixtures computed from the published algorithm. None are real people.
    func testCheckLettersPerSeries() {
        XCTAssertEqual(NRIC.validate("S9912345A")?.checksumOK, true)
        XCTAssertEqual(NRIC.validate("T0012345A")?.checksumOK, true)
        XCTAssertEqual(NRIC.validate("F1234567N")?.checksumOK, true)
        XCTAssertEqual(NRIC.validate("G1234567X")?.checksumOK, true)
        XCTAssertEqual(NRIC.validate("M1234567K")?.checksumOK, true)   // M-table unverified vs real card; see NRIC.swift
        XCTAssertEqual(NRIC.validate("S0000001I")?.checksumOK, true)
    }

    func testWrongLetterFails() {
        let r = NRIC.validate("S9912345B")
        XCTAssertEqual(r?.checksumOK, false)
        XCTAssertEqual(r?.expectedLetter, "A")
    }

    func testFormatRejects() {
        XCTAssertNil(NRIC.validate("A1234567B"))
        XCTAssertNil(NRIC.validate("S123456A"))
        XCTAssertNil(NRIC.validate("S12345678A"))
    }

    func testCaseAndSpacesTolerated() {
        XCTAssertEqual(NRIC.validate(" s9912345a ")?.checksumOK, true)
    }

    func testCenturyHint() {
        XCTAssertEqual(NRIC.validate("S9912345A")?.birthCenturyHint, 1900)
        XCTAssertEqual(NRIC.validate("T0012345A")?.birthCenturyHint, 2000)
        XCTAssertNil(NRIC.validate("F1234567N")?.birthCenturyHint)
    }

    func testFindInOCR() {
        let ocr = ["IDENTITY CARD NO. S9912345A", "Name TAN EVAN", "Address 123 BEDOK NORTH ST 1 #05-123 SINGAPORE 460123"]
        XCTAssertEqual(NRIC.find(in: ocr)?.value, "S9912345A")
        XCTAssertEqual(NRIC.findPostalCode(in: ocr.joined(separator: "\n")), "460123")
    }
}

final class ChinaIDTests: XCTestCase {

    func testPublishedSample() {
        // 11010519491231002X is the widely circulated public example with check 'X'.
        let r = ChinaID.validate("11010519491231002X")
        XCTAssertEqual(r?.checksumOK, true)
        XCTAssertEqual(r?.regionCode, "110105")
        XCTAssertEqual(r?.dateOfBirthISO, "1949-12-31")
        XCTAssertEqual(r?.dateOfBirthValid, true)
        XCTAssertEqual(r?.sex, .female)   // sequence 002 → even
    }

    func testComputedFixtures() {
        let r = ChinaID.validate("610113198506150012")
        XCTAssertEqual(r?.checksumOK, true)
        XCTAssertEqual(r?.regionCode, "610113")       // 西安市雁塔区
        XCTAssertEqual(r?.dateOfBirthISO, "1985-06-15")
        XCTAssertEqual(r?.sex, .male)                 // sequence 001 → odd
        XCTAssertEqual(ChinaID.validate("110101199001010015")?.checksumOK, true)
    }

    func testLowercaseXAccepted() {
        XCTAssertEqual(ChinaID.validate("11010519491231002x")?.checksumOK, true)
    }

    func testWrongCheckFails() {
        let r = ChinaID.validate("110105194912310021")
        XCTAssertEqual(r?.checksumOK, false)
        XCTAssertEqual(r?.expectedCheck, "X")
    }

    func testImpossibleDateFlagged() {
        // 1985-02-30 does not exist; the checksum can still pass, so dateOfBirthValid must catch it.
        let first17 = "61011319850230001"
        let check = ChinaID.expectedCheck(first17: first17)!
        let r = ChinaID.validate(first17 + String(check))
        XCTAssertEqual(r?.checksumOK, true)
        XCTAssertEqual(r?.dateOfBirthValid, false)
    }

    func testFindInOCRWithSpacing() {
        let ocr = ["姓名 王伟", "性别 男 民族 汉", "公民身份号码 610113 19850615 0012"]
        XCTAssertEqual(ChinaID.find(in: ocr)?.value, "610113198506150012")
    }

    func testValidityParsing() {
        let v = ChinaID.parseValidity("有效期限 2015.06.15-2035.06.15")
        XCTAssertEqual(v?.from, "2015-06-15")
        XCTAssertEqual(v?.to, "2035-06-15")
        let longTerm = ChinaID.parseValidity("有效期限 2015.06.15-长期")
        XCTAssertEqual(longTerm?.from, "2015-06-15")
        XCTAssertNil(longTerm?.to)
    }
}

final class TextRulesTests: XCTestCase {

    func testLanguageDetection() {
        XCTAssertEqual(TextRules.detectLanguage("REPUBLIC OF SINGAPORE PASSPORT"), .english)
        XCTAssertEqual(TextRules.detectLanguage("甲方：西安某某制造有限公司 乙方：李某某"), .chineseSimplified)
        XCTAssertEqual(TextRules.detectLanguage("Lease Agreement 租赁合同 between Party A 甲方 and Party B 乙方 for premises"), .mixed)
    }

    func testDateParsing() {
        XCTAssertEqual(TextRules.firstISODate(in: "Date of birth 12 APR 1999"), "1999-04-12")
        XCTAssertEqual(TextRules.firstISODate(in: "Date of birth 12-04-1999"), "1999-04-12")
        XCTAssertEqual(TextRules.firstISODate(in: "出生 1985年6月15日"), "1985-06-15")
        XCTAssertEqual(TextRules.firstISODate(in: "Paid 10 OCT 2026"), "2026-10-10")
        XCTAssertEqual(TextRules.firstISODate(in: "2026.10.10 发票"), "2026-10-10")
        XCTAssertEqual(TextRules.firstISODate(in: "October 10, 2026"), "2026-10-10")
        XCTAssertNil(TextRules.firstISODate(in: "no date here"))
    }

    func testMoneyParsing() {
        let m = TextRules.findMoney(in: "Fare SGD 380.00  Taxes & fees SGD 32.00  Total S$412.00")
        XCTAssertEqual(m.map(\.amount), [380, 32, 412])
        XCTAssertEqual(Set(m.map(\.currency)), ["SGD"])
        let cn = TextRules.findMoney(in: "合同总价 人民币1,250,000元")
        XCTAssertEqual(cn.first?.currency, "CNY")
        XCTAssertEqual(cn.first?.amount, 1_250_000)
    }

    func testReceiptLinesSumToTotal() {
        let m = TextRules.findMoney(in: "Fare SGD 380.00\nTaxes SGD 32.00\nTotal SGD 412.00")
        let total = m.last!.amount
        let lines = m.dropLast().reduce(Decimal(0)) { $0 + $1.amount }
        XCTAssertEqual(lines, total)
    }
}

final class ModelTests: XCTestCase {
    func testSensitiveDefaults() {
        XCTAssertTrue(DocumentType.passport.isSensitiveByDefault)
        XCTAssertTrue(DocumentType.bankCard.isSensitiveByDefault)
        XCTAssertFalse(DocumentType.receipt.isSensitiveByDefault)
    }
    func testClientRetentionDefaults() {
        XCTAssertEqual(PersonKind.client.defaultAutoExpireDays, 30)
        XCTAssertNil(PersonKind.family.defaultAutoExpireDays)
        XCTAssertEqual(RetentionPolicy.warnDaysBefore, 3)
    }
    func testConfidenceTiers() {
        XCTAssertEqual(FieldCheck.mrz.confidenceTier, .verified)
        XCTAssertEqual(FieldCheck.ocr.confidenceTier, .unverified)
        XCTAssertEqual(FieldCheck.missing.confidenceTier, .missing)
    }
}
