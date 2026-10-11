import Foundation

// MARK: - Passport

public enum PassportExtractor {
    public static func extract(lines: [String], now: Date = Date()) -> ExtractionResult {
        var fields: [ExtractedField] = []
        var warnings: [String] = []
        var passed = 0, total = 0

        let visualSurname = LabelReader.value(after: ["Surname", "Family name", "姓"], in: lines)
        let visualGiven = LabelReader.value(after: ["Given names", "Given name", "Names", "名"], in: lines)
        let visualNumber = LabelReader.value(after: ["Passport No", "Passport Number", "Document No", "护照号"], in: lines)
        let visualDOB = LabelReader.value(after: ["Date of birth", "Birth", "出生日期"], in: lines).flatMap(TextRules.firstISODate)
        let visualExpiry = LabelReader.value(after: ["Date of expiry", "Expiry", "Expires", "有效期至"], in: lines).flatMap(TextRules.firstISODate)
        let issueDate = LabelReader.value(after: ["Date of issue", "Issued on", "签发日期"], in: lines).flatMap(TextRules.firstISODate)
        let placeOfIssue = LabelReader.value(after: ["Place of issue", "Authority", "Issuing authority", "签发地点", "签发机关"], in: lines)
        let placeOfBirth = LabelReader.value(after: ["Place of birth", "Country of birth", "出生地点"], in: lines)

        if let (l1, l2) = MRZ.locateLines(in: lines), let td3 = try? MRZ.parseTD3(line1: l1, line2: l2) {
            total = 5
            passed = [td3.documentNumberCheckOK, td3.dateOfBirthCheckOK, td3.expiryCheckOK, td3.optionalDataCheckOK, td3.compositeCheckOK].filter { $0 }.count
            if !td3.allChecksOK { warnings.append("MRZ check digit failed — likely a misread. Edit or retake.") }

            fields.append(LabelReader.field("surname", "Surname", "姓", td3.surname, .mrz))
            fields.append(LabelReader.field("givenNames", "Given names", "名", td3.givenNames, .mrz))
            fields.append(LabelReader.field("passportNumber", "Passport no.", "护照号码", td3.documentNumber, td3.documentNumberCheckOK ? .mrz : .ocr))
            fields.append(LabelReader.field("nationality", "Nationality", "国籍", td3.nationality, .mrz))
            fields.append(LabelReader.field("issuingCountry", "Issuing country", "签发国", td3.issuingCountry, .mrz))
            fields.append(LabelReader.field("dateOfBirth", "Date of birth", "出生日期", td3.isoDateOfBirth(now: now), td3.dateOfBirthCheckOK ? .mrz : .ocr))
            fields.append(LabelReader.field("sex", "Sex", "性别", td3.sex == "<" ? nil : td3.sex, .mrz))
            fields.append(LabelReader.field("expiry", "Expiry", "有效期至", td3.isoExpiryDate(now: now), td3.expiryCheckOK ? .mrz : .ocr))

            // Cross-check visual zone against MRZ; disagreement is a warning, MRZ wins.
            if let v = visualNumber?.uppercased().filter({ $0.isLetter || $0.isNumber }), v != td3.documentNumber, td3.documentNumberCheckOK {
                warnings.append("Printed passport number (\(v)) differs from MRZ (\(td3.documentNumber)). MRZ used.")
            }
            if let v = visualExpiry, v != td3.isoExpiryDate(now: now) { warnings.append("Printed expiry \(v) differs from MRZ \(td3.isoExpiryDate(now: now)).") }
        } else {
            warnings.append("No MRZ found. All fields are OCR only.")
            fields.append(LabelReader.field("surname", "Surname", "姓", visualSurname, .ocr))
            fields.append(LabelReader.field("givenNames", "Given names", "名", visualGiven, .ocr))
            fields.append(LabelReader.field("passportNumber", "Passport no.", "护照号码", visualNumber, .ocr))
            fields.append(LabelReader.field("nationality", "Nationality", "国籍", LabelReader.value(after: ["Nationality", "国籍"], in: lines), .ocr))
            fields.append(LabelReader.field("dateOfBirth", "Date of birth", "出生日期", visualDOB, .regex))
            fields.append(LabelReader.field("sex", "Sex", "性别", LabelReader.value(after: ["Sex", "性别"], in: lines).map { String($0.prefix(1)).uppercased() }, .ocr))
            fields.append(LabelReader.field("expiry", "Expiry", "有效期至", visualExpiry, .regex))
        }
        fields.append(LabelReader.field("issueDate", "Issue date", "签发日期", issueDate, .regex))
        fields.append(LabelReader.field("placeOfIssue", "Place of issue", "签发地点", placeOfIssue, .ocr))
        fields.append(LabelReader.field("placeOfBirth", "Place of birth", "出生地点", placeOfBirth, .ocr, section: .secondary))

        if let exp = fields.first(where: { $0.key == "expiry" })?.value, let d = ISO.date(exp) {
            let months = Calendar(identifier: .gregorian).dateComponents([.month], from: now, to: d).month ?? 0
            if months < 9 { warnings.append("Expires in \(max(months, 0)) months — many countries need 6 months validity.") }
        }
        return ExtractionResult(type: .passport, fields: fields, warnings: warnings, checksPassed: passed, checksTotal: total)
    }
}

// MARK: - Singapore NRIC / FIN

public enum NRICExtractor {
    public static func extract(lines: [String]) -> ExtractionResult {
        var fields: [ExtractedField] = []
        var warnings: [String] = []
        var passed = 0, total = 0
        let text = lines.joined(separator: "\n")

        let n = NRIC.find(in: lines)
        if let n {
            total += 1; if n.checksumOK { passed += 1 } else { warnings.append("NRIC checksum fails — expected letter \(n.expectedLetter).") }
            if n.series == .fin2022 && !n.checksumOK { warnings.append("M-series FIN check table is unverified; treat as unverified, not wrong.") }
        }
        fields.append(LabelReader.field("nric", "NRIC / FIN", "身份证号", n?.value, (n?.checksumOK ?? false) ? .nric : .ocr))
        let name = LabelReader.value(after: ["Name", "姓名"], in: lines)
        fields.append(LabelReader.field("name", "Name", "姓名", name, .ocr))
        let dob = LabelReader.value(after: ["Date of birth", "Date of Birth", "DOB", "出生日期"], in: lines).flatMap(TextRules.firstISODate)
        if let dob, let n, let century = n.birthCenturyHint, let y = Int(dob.prefix(4)) {
            total += 1
            if (y >= century && y < century + 100) { passed += 1 } else { warnings.append("DOB year \(y) does not match NRIC prefix \(n.series.rawValue).") }
        }
        fields.append(LabelReader.field("dateOfBirth", "Date of birth", "出生日期", dob, .regex))
        fields.append(LabelReader.field("sex", "Sex", "性别", LabelReader.value(after: ["Sex", "性别"], in: lines).map { String($0.prefix(1)).uppercased() }, .ocr))
        fields.append(LabelReader.field("placeOfBirth", "Country / place of birth", "出生地", LabelReader.value(after: ["Country/Place of birth", "Place of birth", "Country of birth"], in: lines), .ocr))
        let address = LabelReader.value(after: ["Address", "地址"], in: lines, maxNextLines: 2)
        fields.append(LabelReader.field("address", "Address", "地址", address, .ocr))
        fields.append(LabelReader.field("postalCode", "Postal code", "邮政编码", NRIC.findPostalCode(in: text), .regex))
        fields.append(LabelReader.field("issueDate", "Date of issue", "签发日期", LabelReader.value(after: ["Date of issue", "Date of Issue"], in: lines).flatMap(TextRules.firstISODate), .regex))
        // Secondary (kept apart, per Evan)
        fields.append(LabelReader.field("race", "Race", "种族", LabelReader.value(after: ["Race"], in: lines).map { $0.components(separatedBy: " ").first ?? $0 }, .ocr, section: .secondary))
        fields.append(LabelReader.field("bloodGroup", "Blood group", "血型", LabelReader.value(after: ["Blood Group", "Blood group"], in: lines).map { $0.components(separatedBy: " ").first ?? $0 }, .ocr, section: .secondary))
        return ExtractionResult(type: .nric, fields: fields, warnings: warnings, checksPassed: passed, checksTotal: total)
    }
}

// MARK: - PRC 居民身份证

public enum ChinaIDExtractor {
    public static func extract(lines: [String]) -> ExtractionResult {
        var fields: [ExtractedField] = []
        var warnings: [String] = []
        var passed = 0, total = 0
        let text = lines.joined(separator: "\n")

        let id = ChinaID.find(in: lines)
        if let id {
            total += 1; if id.checksumOK { passed += 1 } else { warnings.append("身份证 checksum fails — expected \(id.expectedCheck).") }
        }
        let name = LabelReader.value(after: ["姓名", "Name"], in: lines).map { $0.replacingOccurrences(of: " ", with: "") }
        fields.append(LabelReader.field("name", "Name", "姓名", name, .ocr))
        // Pinyin guess from the characters; the review screen lets the user mark surname vs given name and the order.
        let split = name.flatMap(Pinyin.split)
        fields.append(LabelReader.field("namePinyin", "Pinyin", "拼音", split?.formatted, .ocr))
        fields.append(LabelReader.field("surnamePinyin", "Surname (pinyin)", "姓", split?.surname, .ocr))
        fields.append(LabelReader.field("givenNamePinyin", "Given name (pinyin)", "名", split?.givenName, .ocr))
        fields.append(LabelReader.field("idNumber", "ID number", "公民身份号码", id?.value, (id?.checksumOK ?? false) ? .cnid : .ocr))

        let printedDOB = LabelReader.value(after: ["出生", "Date of birth"], in: lines).flatMap(TextRules.firstISODate)
        if let id {
            total += 1
            if printedDOB == nil || printedDOB == id.dateOfBirthISO { passed += 1 } else { warnings.append("Printed 出生 \(printedDOB!) differs from ID digits \(id.dateOfBirthISO).") }
            if !id.dateOfBirthValid { warnings.append("ID digits encode an impossible date.") }
        }
        fields.append(LabelReader.field("dateOfBirth", "Date of birth", "出生", id?.dateOfBirthISO ?? printedDOB, id != nil ? .cnid : .regex))

        let printedSex = LabelReader.value(after: ["性别", "Sex"], in: lines).map { String($0.prefix(1)) }
        if let id {
            total += 1
            if printedSex == nil || printedSex == id.sex.zh { passed += 1 } else { warnings.append("Printed 性别 \(printedSex!) differs from ID digit (\(id.sex.zh)).") }
        }
        fields.append(LabelReader.field("sex", "Sex", "性别", id.map { "\($0.sex.zh) \($0.sex.rawValue)" } ?? printedSex, id != nil ? .cnid : .ocr))
        fields.append(LabelReader.field("address", "Address", "住址", LabelReader.value(after: ["住址", "Address"], in: lines, maxNextLines: 2), .ocr))
        fields.append(LabelReader.field("issuer", "Issuing authority", "签发机关", LabelReader.value(after: ["签发机关"], in: lines), .ocr))
        if let v = ChinaID.parseValidity(LabelReader.value(after: ["有效期限", "有效期"], in: lines) ?? text) {
            fields.append(LabelReader.field("validFrom", "Valid from", "有效期自", v.from, .regex))
            fields.append(LabelReader.field("validTo", "Valid to", "有效期至", v.to ?? "长期", .regex))
        } else {
            fields.append(LabelReader.field("validFrom", "Valid from", "有效期自", nil, .missing))
            fields.append(LabelReader.field("validTo", "Valid to", "有效期至", nil, .missing))
        }
        fields.append(LabelReader.field("regionCode", "Region code", "地区码", id?.regionCode, .cnid))
        fields.append(LabelReader.field("ethnicity", "Ethnicity", "民族", LabelReader.value(after: ["民族"], in: lines).map { String($0.prefix(while: { !$0.isWhitespace })) }, .ocr, section: .secondary))
        return ExtractionResult(type: .chinaID, fields: fields, warnings: warnings, checksPassed: passed, checksTotal: total)
    }
}

// MARK: - Bank card

public enum BankCardExtractor {
    public static func extract(lines: [String], now: Date = Date()) -> ExtractionResult {
        var fields: [ExtractedField] = []
        var warnings: [String] = []
        var passed = 0, total = 0

        let card = CardCheck.findCardNumber(in: lines)
        if let card {
            total += 1; if card.luhnOK { passed += 1 } else { warnings.append("Card number fails Luhn — likely a misread digit.") }
        }
        fields.append(LabelReader.field("pan", "Card number", "卡号", card?.digits, (card?.luhnOK ?? false) ? .luhn : .ocr))
        fields.append(LabelReader.field("brand", "Brand", "卡组织", card?.brand.rawValue, .luhn))
        fields.append(LabelReader.field("last4", "Last 4", "末四位", card?.last4, .luhn))

        let expLine = lines.first { CardCheck.parseExpiry($0) != nil }
        if let expLine, let e = CardCheck.parseExpiry(expLine) {
            total += 1
            if CardCheck.expiryIsCurrentOrFuture(month: e.month, year: e.year, now: now) { passed += 1 } else { warnings.append("Card expiry is in the past.") }
            fields.append(LabelReader.field("expiry", "Expiry", "有效期", String(format: "%02d/%02d", e.month, e.year % 100), .regex))
        } else {
            fields.append(LabelReader.field("expiry", "Expiry", "有效期", nil, .missing))
        }
        // Name on card: an all-caps line with 2–4 words, no digits, not a brand/bank word.
        let banned = ["VISA", "MASTERCARD", "DEBIT", "CREDIT", "VALID", "THRU", "PLATINUM", "GOLD", "WORLD", "ELITE", "ALTITUDE", "DBS", "OCBC", "UOB", "POSB", "CITI", "HSBC", "AMEX", "UNIONPAY"]
        let name = lines.first { l in
            let words = l.split(separator: " ")
            return l == l.uppercased() && (2...4).contains(words.count) && !l.contains(where: \.isNumber)
                && !words.contains { banned.contains(String($0)) }
        }
        fields.append(LabelReader.field("nameOnCard", "Name on card", "持卡人", name, .ocr))
        let issuer = lines.first { l in ["DBS", "OCBC", "UOB", "POSB", "CITI", "HSBC", "STANDARD CHARTERED", "MAYBANK", "ICBC", "中国银行", "建设银行", "工商银行", "招商银行"].contains { l.uppercased().contains($0) } }
        fields.append(LabelReader.field("issuer", "Issuer", "发卡行", issuer, .ocr))
        fields.append(LabelReader.field("cardLabel", "Card name", "卡名", nil, .missing))   // user names it, e.g. "DBS Altitude"
        let cvv: String? = LabelReader.value(after: ["CVV", "CVC", "CVV2"], in: lines).flatMap { raw -> String? in
            guard let r = raw.range(of: #"\d{3,4}"#, options: .regularExpression) else { return nil }
            return String(raw[r])
        }
        fields.append(LabelReader.field("cvv", "CVV", "安全码", cvv, .ocr, section: .secondary))
        return ExtractionResult(type: .bankCard, fields: fields, warnings: warnings, checksPassed: passed, checksTotal: total)
    }
}

enum ISO {
    static func date(_ s: String) -> Date? {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }
}
