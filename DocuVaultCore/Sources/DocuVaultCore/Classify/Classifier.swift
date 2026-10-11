import Foundation

/// Rules-first document classifier. Scores every type from OCR lines; the review screen shows the reasons.
/// A model fallback (Apple on-device) is used by the app only when the top score is below `modelThreshold`.
public enum Classifier {

    public struct Reason: Equatable, Sendable {
        public let text: String
        public let points: Int
    }

    public struct Verdict: Equatable, Sendable {
        public let type: DocumentType
        public let score: Int
        public let reasons: [Reason]
        /// All candidates sorted by score, for the "Change type" screen.
        public let ranked: [(DocumentType, Int)]

        public static func == (a: Verdict, b: Verdict) -> Bool {
            a.type == b.type && a.score == b.score && a.reasons == b.reasons
        }
    }

    /// Below this, the app asks the on-device model (if available); otherwise the type is `.other`.
    public static let modelThreshold = 40

    public static func classify(lines rawLines: [String]) -> Verdict {
        let lines = rawLines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let upper = lines.map { $0.uppercased() }
        let joined = upper.joined(separator: "\n")
        var scores: [DocumentType: Int] = [:]
        var reasons: [DocumentType: [Reason]] = [:]
        func add(_ t: DocumentType, _ pts: Int, _ why: String) {
            scores[t, default: 0] += pts
            reasons[t, default: []].append(Reason(text: why, points: pts))
        }

        // Passport
        if let (l1, l2) = MRZ.locateLines(in: lines) {
            add(.passport, 60, "Two 44-character MRZ lines found")
            if let td3 = try? MRZ.parseTD3(line1: l1, line2: l2), td3.allChecksOK {
                add(.passport, 30, "MRZ check digits all pass")
            }
        }
        if joined.contains("PASSPORT") || joined.contains("护照") { add(.passport, 8, "Word \"PASSPORT\" / 护照 present") }

        // NRIC / FIN
        if let n = NRIC.find(in: lines) {
            add(.nric, n.checksumOK ? 70 : 30, n.checksumOK ? "NRIC/FIN with valid checksum" : "NRIC/FIN-shaped token (checksum fails)")
        }
        if joined.contains("IDENTITY CARD") || joined.contains("REPUBLIC OF SINGAPORE") { add(.nric, 10, "Singapore identity card wording") }

        // China ID
        if let c = ChinaID.find(in: lines) {
            add(.chinaID, c.checksumOK ? 70 : 30, c.checksumOK ? "18-digit 身份证 with valid checksum" : "18-digit number (checksum fails)")
        }
        if joined.contains("居民身份证") || joined.contains("公民身份号码") { add(.chinaID, 15, "居民身份证 / 公民身份号码 wording") }

        // Bank card
        if let card = CardCheck.findCardNumber(in: lines), card.luhnOK {
            add(.bankCard, 50, "Luhn-valid card number")
            if card.brand != .unknown { add(.bankCard, 10, "Brand recognised: \(card.brand.rawValue)") }
            if lines.contains(where: { CardCheck.parseExpiry($0) != nil }) { add(.bankCard, 20, "Expiry MM/YY present") }
        }
        if joined.contains("VALID THRU") || joined.contains("VALID FROM") || joined.contains("DEBIT") || joined.contains("CREDIT CARD") {
            add(.bankCard, 8, "Card wording present")
        }

        // Receipt
        let receiptMarkers = ["TOTAL", "SUBTOTAL", "GST", "合计", "总计", "发票", "小计", "AMOUNT DUE", "CHANGE", "CASH", "RECEIPT", "INVOICE", "实付", "应付"]
        let rm = receiptMarkers.filter { joined.contains($0) }
        if !rm.isEmpty { add(.receipt, min(50, rm.count * 25), "Receipt words: \(rm.prefix(3).joined(separator: ", "))") }
        let money = TextRules.findMoney(in: lines.joined(separator: "\n"))
        if money.count >= 2 { add(.receipt, min(20, money.count * 10), "\(money.count) money amounts") }

        // Contract
        let contractMarkers = ["AGREEMENT", "合同", "协议", "甲方", "乙方", "PARTY A", "PARTY B", "WHEREAS", "HEREINAFTER", "GOVERNING LAW", "适用法律", "违约", "TERM AND TERMINATION", "LESSOR", "LESSEE"]
        let cm = contractMarkers.filter { joined.contains($0) }
        if !cm.isEmpty { add(.contract, min(70, cm.count * 20), "Contract words: \(cm.prefix(3).joined(separator: ", "))") }

        // Business card
        let hasEmail = joined.range(of: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, options: .regularExpression) != nil
        let hasPhone = joined.range(of: #"(\+?\d[\d\s\-]{7,}\d)"#, options: .regularExpression) != nil
        if hasEmail && hasPhone && lines.count <= 12 { add(.businessCard, 60, "Email + phone on a short card") }

        // Letter
        let letterMarkers = ["DEAR ", "YOURS SINCERELY", "YOURS FAITHFULLY", "KIND REGARDS", "敬启", "此致", "敬礼", "TO WHOM IT MAY CONCERN"]
        let lm = letterMarkers.filter { joined.contains($0) }
        if !lm.isEmpty { add(.letter, 40, "Letter wording: \(lm.first!)") }

        // Penalties: a passport page also mentions "IDENTITY"; prefer the strongest checksum evidence.
        let ranked = scores.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
        guard let top = ranked.first, top.1 >= modelThreshold else {
            return Verdict(type: .other, score: ranked.first?.1 ?? 0,
                           reasons: ranked.first.flatMap { reasons[$0.0] } ?? [], ranked: ranked)
        }
        return Verdict(type: top.0, score: top.1, reasons: reasons[top.0] ?? [], ranked: ranked)
    }
}
