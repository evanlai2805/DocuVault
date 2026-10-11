import Foundation

// MARK: - Receipt

public enum ReceiptExtractor {
    public static var categories: [String] { ExpenseCategories.names }

    public static func extract(lines: [String]) -> ExtractionResult {
        var fields: [ExtractedField] = []
        var warnings: [String] = []
        var passed = 0, total = 0
        let text = lines.joined(separator: "\n")
        let upper = lines.map { $0.uppercased() }

        // Merchant: first line with letters that is not a date, amount, or generic word.
        let merchant = lines.prefix(5).first { l in
            let letters = l.filter(\.isLetter).count
            return letters >= 3 && TextRules.firstISODate(in: l) == nil && TextRules.findMoney(in: l).isEmpty
                && !["RECEIPT", "INVOICE", "TAX INVOICE", "发票"].contains(l.uppercased())
        }
        fields.append(LabelReader.field("merchant", "Merchant", "商户", merchant, .ocr))

        // Date: prefer a line with a date label, else first date anywhere.
        let date = LabelReader.value(after: ["Date", "日期", "Paid"], in: lines).flatMap(TextRules.firstISODate) ?? TextRules.firstISODate(in: text)
        fields.append(LabelReader.field("date", "Date", "日期", date, .regex))

        // Total: the amount on a line containing TOTAL/合计/总计/实付, preferring the last such line.
        let totalLineIdx = upper.indices.last { i in
            let l = upper[i]
            return (l.contains("TOTAL") && !l.contains("SUBTOTAL")) || l.contains("合计") || l.contains("总计") || l.contains("实付") || l.contains("AMOUNT DUE")
        }
        let totalMoney = totalLineIdx.flatMap { TextRules.findMoney(in: lines[$0]).last }
        let allMoney = TextRules.findMoney(in: text)
        let total_ = totalMoney ?? allMoney.max { $0.amount < $1.amount }
        let currency = total_?.currency ?? allMoney.first?.currency
        fields.append(LabelReader.field("currency", "Currency", "币种", currency, .regex))

        if let t = total_ {
            // Sum check: do the other amounts (excluding the total line) add up to the total?
            let others = allMoney.filter { $0.currency == t.currency }.map(\.amount)
            let candidates = others.filter { $0 != t.amount }
            total += 1
            if !candidates.isEmpty && candidates.reduce(0, +) == t.amount {
                passed += 1
                fields.append(LabelReader.field("total", "Total", "总额", Self.money(t.amount), .regex))
            } else {
                // Not a failure of the document, just unverified.
                total -= 1
                fields.append(LabelReader.field("total", "Total", "总额", Self.money(t.amount), .ocr))
            }
        } else {
            fields.append(LabelReader.field("total", "Total", "总额", nil, .missing))
        }

        // Tax
        let taxIdx = upper.indices.first { upper[$0].contains("GST") || upper[$0].contains("TAX") || upper[$0].contains("增值税") || upper[$0].contains("税额") }
        let tax = taxIdx.flatMap { TextRules.findMoney(in: lines[$0]).last?.amount }
        fields.append(LabelReader.field("tax", "Tax", "税额", tax.map(Self.money), .ocr))
        if let tax, let t = total_, t.amount > 0, currency == "SGD" {
            let rate = NSDecimalNumber(decimal: tax / t.amount).doubleValue
            if rate > 0.10 { warnings.append("Tax is \(Int(rate * 100))% of total — SG GST is 9%.") }
        }

        // Payment
        let last4 = text.range(of: #"\*{2,}\s?(\d{4})"#, options: .regularExpression).map { String(text[$0].suffix(4)) }
        fields.append(LabelReader.field("cardLast4", "Card last 4", "卡末四位", last4, .regex))
        let method = upper.contains { $0.contains("VISA") } ? "Visa" : upper.contains { $0.contains("MASTERCARD") } ? "Mastercard"
            : upper.contains { $0.contains("AMEX") } ? "Amex" : upper.contains { $0.contains("PAYNOW") } ? "PayNow"
            : upper.contains { $0.contains("微信") || $0.contains("WECHAT") } ? "WeChat Pay" : upper.contains { $0.contains("支付宝") || $0.contains("ALIPAY") } ? "Alipay"
            : upper.contains { $0.contains("CASH") || $0.contains("现金") } ? "Cash" : nil
        fields.append(LabelReader.field("paymentMethod", "Payment", "支付方式", method, .ocr))
        let ref = LabelReader.value(after: ["Booking ref", "Reference", "Ref No", "Receipt No", "Invoice No", "订单号", "发票号码", "Order"], in: lines)
            .map { String($0.prefix(while: { !$0.isWhitespace })) }
        fields.append(LabelReader.field("reference", "Reference", "单号", ref, .ocr))
        fields.append(LabelReader.field("category", "Category", "类别", ExpenseCategories.guess(from: text), .ocr))
        return ExtractionResult(type: .receipt, fields: fields, warnings: warnings, checksPassed: passed, checksTotal: total)
    }

    static func money(_ d: Decimal) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.minimumFractionDigits = 2; f.maximumFractionDigits = 2
        f.locale = Locale(identifier: "en_US_POSIX"); f.usesGroupingSeparator = false
        return f.string(from: d as NSDecimalNumber) ?? "\(d)"
    }

    /// CSV row: date,merchant,category,currency,total,tax,card_last4,ref
    public static func csvRow(_ r: ExtractionResult) -> String {
        func v(_ k: String) -> String {
            let s = r.fields.first { $0.key == k }?.value ?? ""
            return s.contains(",") || s.contains("\"") ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
        }
        return [v("date"), v("merchant"), v("category"), v("currency"), v("total"), v("tax"), v("cardLast4"), v("reference")].joined(separator: ",")
    }
    public static let csvHeader = "date,merchant,category,currency,total,tax,card_last4,ref"
}

// MARK: - Contract / letter

public enum ContractExtractor {
    public static func extract(lines: [String], type: DocumentType) -> ExtractionResult {
        var fields: [ExtractedField] = []
        let text = lines.joined(separator: "\n")

        let partyA = LabelReader.value(after: ["甲方（出租方）", "甲方(出租方)", "甲方（买方）", "甲方", "Party A", "Lessor", "Landlord", "Seller", "Between"], in: lines)
        let partyB = LabelReader.value(after: ["乙方（承租方）", "乙方(承租方)", "乙方（卖方）", "乙方", "Party B", "Lessee", "Tenant", "Buyer", " and "], in: lines)
        fields.append(LabelReader.field("partyA", "Party A", "甲方", partyA, .ocr))
        fields.append(LabelReader.field("partyB", "Party B", "乙方", partyB, .ocr))

        // Dates: first two ISO dates in the document; the earlier is "effective", the later "expiry" when both exist.
        let dates = TextRules.allISODates(in: text)
        fields.append(LabelReader.field("effectiveDate", "Effective date", "生效日期", dates.first, .regex))
        fields.append(LabelReader.field("expiryDate", "End date", "到期日期", dates.count >= 2 ? dates.max() : nil, .regex))

        let money = TextRules.findMoney(in: text)
        let amounts = money.prefix(5).map { "\($0.currency) \(ReceiptExtractor.money($0.amount))" }.joined(separator: " · ")
        fields.append(LabelReader.field("amounts", "Amounts", "金额", amounts.isEmpty ? nil : amounts, .regex))

        let law = LabelReader.value(after: ["Governing law", "governed by the laws of", "适用法律", "本合同适用"], in: lines)
        fields.append(LabelReader.field("governingLaw", "Governing law", "适用法律", law, .ocr))
        let title = lines.first { l in
            let u = l.uppercased()
            return ["AGREEMENT", "CONTRACT", "合同", "协议", "LEASE", "DEED"].contains { u.contains($0) } && l.count <= 60
        }
        fields.append(LabelReader.field("title", "Title", "标题", title, .ocr))
        return ExtractionResult(type: type, fields: fields)
    }

}

// MARK: - Business card

public enum BusinessCardExtractor {
    public static func extract(lines: [String]) -> ExtractionResult {
        var fields: [ExtractedField] = []
        let text = lines.joined(separator: "\n")
        let email = text.range(of: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, options: .regularExpression).map { String(text[$0]) }
        let phone = text.range(of: #"\+?\d[\d\s\-]{7,}\d"#, options: .regularExpression).map { String(text[$0]).replacingOccurrences(of: " ", with: "") }
        let website = text.range(of: #"(https?://|www\.)[A-Za-z0-9.-]+\.[A-Za-z]{2,}(/\S*)?"#, options: .regularExpression).map { String(text[$0]) }
        let name = lines.first { l in
            let words = l.split(separator: " ")
            let cjk = l.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }.count
            return (cjk >= 2 && cjk <= 4 && l.count <= 4) || ((2...3).contains(words.count) && !l.contains("@") && !l.contains(where: \.isNumber) && l.count <= 30)
        }
        let titleWords = ["DIRECTOR", "MANAGER", "PARTNER", "ANALYST", "CEO", "CFO", "总经理", "经理", "董事", "总监", "合伙人"]
        let title = lines.first { l in titleWords.contains { l.uppercased().contains($0) } }
        let company = lines.first { l in
            let u = l.uppercased()
            return ["PTE", "LTD", "LLP", "INC", "有限公司", "集团", "CO.,"].contains { u.contains($0) }
        }
        fields.append(LabelReader.field("name", "Name", "姓名", name, .ocr))
        fields.append(LabelReader.field("title", "Title", "职位", title, .ocr))
        fields.append(LabelReader.field("company", "Company", "公司", company, .ocr))
        fields.append(LabelReader.field("phone", "Phone", "电话", phone, .regex))
        fields.append(LabelReader.field("email", "Email", "邮箱", email, .regex))
        fields.append(LabelReader.field("website", "Website", "网站", website, .regex))
        return ExtractionResult(type: .businessCard, fields: fields)
    }
}
