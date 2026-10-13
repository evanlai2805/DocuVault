import Foundation

/// How the keyboard renders a stored value into a form. Pure functions; the keyboard remembers the last choice.
public enum FillFormats {

    /// Declaration order is the order the hold panel shows them.
    public enum DateStyle: String, CaseIterable, Codable, Sendable {
        case dmySlash = "DD/MM/YYYY"
        case iso = "YYYY-MM-DD"
        case dMonYSlash = "DD/MMM/YYYY"
        case dMonYDash = "DD-MMM-YYYY"
        case dMonY = "DD Mon YYYY"
        case digitsDMY = "DDMMYYYY"
        case mdySlash = "MM/DD/YYYY"
        case digitsYMD = "YYYYMMDD"

        public static let `default`: DateStyle = .iso
    }

    static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// Format an ISO yyyy-MM-dd value. Returns the input unchanged if it is not ISO.
    public static func date(_ iso: String, style: DateStyle) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]), (1...12).contains(m) else { return iso }
        let yy = String(format: "%04d", y), mm = String(format: "%02d", m), dd = String(format: "%02d", d)
        switch style {
        case .iso: return "\(yy)-\(mm)-\(dd)"
        case .dmySlash: return "\(dd)/\(mm)/\(yy)"
        case .mdySlash: return "\(mm)/\(dd)/\(yy)"
        case .dMonY: return "\(dd) \(months[m - 1]) \(yy)"
        case .dMonYSlash: return "\(dd)/\(months[m - 1].uppercased())/\(yy)"
        case .dMonYDash: return "\(dd)-\(months[m - 1].uppercased())-\(yy)"
        case .digitsDMY: return "\(dd)\(mm)\(yy)"
        case .digitsYMD: return "\(yy)\(mm)\(dd)"
        }
    }

    /// How the app shows a stored date: 12/MAR/1990 (Evan, checkpoint 14). Storage and export stay ISO.
    /// Returns the input unchanged when it is not an ISO date, so free text such as 长期 passes through.
    public static func display(_ iso: String) -> String {
        date(iso, style: .dMonYSlash)
    }

    /// Card number: digits only by default (most forms reject spaces); spaced on hold.
    public static func cardNumber(_ digits: String, spaced: Bool) -> String {
        let d = digits.filter(\.isNumber)
        guard spaced else { return d }
        let groups = d.count == 15 ? [4, 6, 5] : Array(repeating: 4, count: (d.count + 3) / 4)
        var out: [String] = []
        var i = d.startIndex
        for g in groups where i < d.endIndex {
            let j = d.index(i, offsetBy: g, limitedBy: d.endIndex) ?? d.endIndex
            out.append(String(d[i..<j]))
            i = j
        }
        return out.joined(separator: " ")
    }

    /// Card expiry MM/YY → variants used by forms.
    public enum ExpiryStyle: String, CaseIterable, Codable, Sendable { case mmSlashYY = "MM/YY", mmSlashYYYY = "MM/YYYY", mmyy = "MMYY" }
    public static func expiry(_ mmyy: String, style: ExpiryStyle) -> String {
        let parts = mmyy.split(whereSeparator: { "/-".contains($0) })
        guard parts.count == 2, let m = Int(parts[0]), var y = Int(parts[1]) else { return mmyy }
        if y > 99 { y %= 100 }
        switch style {
        case .mmSlashYY: return String(format: "%02d/%02d", m, y)
        case .mmSlashYYYY: return String(format: "%02d/20%02d", m, y)
        case .mmyy: return String(format: "%02d%02d", m, y)
        }
    }

    /// Singapore 6-digit postcode out of an address line, or the last 6-digit run anywhere.
    public static func postcode(from address: String) -> String? {
        if let p = NRIC.findPostalCode(in: address) { return p }
        let runs = address.split(whereSeparator: { !$0.isNumber }).filter { $0.count == 6 }
        return runs.last.map { String($0) }
    }

    /// Which keys the keyboard shows for a document type, in order, with their field keys and labels.
    public struct KeySpec: Equatable, Sendable {
        public let fieldKey: String
        public let label: String
        public let kind: Kind
        public enum Kind: Sendable { case text, date, cardNumber, expiry, holdOnly }
        public init(fieldKey: String, label: String, kind: Kind) { self.fieldKey = fieldKey; self.label = label; self.kind = kind }
    }

    public static func keys(for type: DocumentType) -> [KeySpec] {
        switch type {
        case .bankCard: return [
            .init(fieldKey: "pan", label: "Number", kind: .cardNumber), .init(fieldKey: "expiry", label: "Expiry", kind: .expiry),
            .init(fieldKey: "cvv", label: "CVV", kind: .holdOnly), .init(fieldKey: "nameOnCard", label: "Name", kind: .text),
            .init(fieldKey: "issuer", label: "Issuer", kind: .text), .init(fieldKey: "last4", label: "Last 4", kind: .text)]
        case .passport: return [
            .init(fieldKey: "passportNumber", label: "Passport no.", kind: .text), .init(fieldKey: "surname", label: "Surname", kind: .text),
            .init(fieldKey: "givenNames", label: "Given names", kind: .text), .init(fieldKey: "dateOfBirth", label: "DOB", kind: .date),
            .init(fieldKey: "expiry", label: "Expiry", kind: .date), .init(fieldKey: "nationality", label: "Nationality", kind: .text),
            .init(fieldKey: "sex", label: "Sex", kind: .text), .init(fieldKey: "issueDate", label: "Issue date", kind: .date),
            .init(fieldKey: "placeOfBirth", label: "Place of birth", kind: .text), .init(fieldKey: "issuingCountry", label: "Issuing country", kind: .text)]
        case .nric: return [
            .init(fieldKey: "nric", label: "NRIC / FIN", kind: .text), .init(fieldKey: "name", label: "Name", kind: .text),
            .init(fieldKey: "dateOfBirth", label: "DOB", kind: .date), .init(fieldKey: "sex", label: "Sex", kind: .text),
            .init(fieldKey: "address", label: "Address", kind: .text), .init(fieldKey: "postalCode", label: "Postcode", kind: .text),
            .init(fieldKey: "placeOfBirth", label: "Place of birth", kind: .text)]
        case .chinaID: return [
            .init(fieldKey: "idNumber", label: "ID number", kind: .text), .init(fieldKey: "name", label: "姓名", kind: .text),
            .init(fieldKey: "namePinyin", label: "Pinyin", kind: .text), .init(fieldKey: "surnamePinyin", label: "Surname", kind: .text),
            .init(fieldKey: "givenNamePinyin", label: "Given name", kind: .text), .init(fieldKey: "dateOfBirth", label: "DOB", kind: .date),
            .init(fieldKey: "sex", label: "Sex", kind: .text), .init(fieldKey: "address", label: "住址", kind: .text),
            .init(fieldKey: "validTo", label: "Valid to", kind: .date)]
        case .businessCard: return [
            .init(fieldKey: "name", label: "Name", kind: .text), .init(fieldKey: "company", label: "Company", kind: .text),
            .init(fieldKey: "phone", label: "Phone", kind: .text), .init(fieldKey: "email", label: "Email", kind: .text)]
        default: return []
        }
    }

    /// Keys for a person's shared fields.
    public static let sharedKeys: [KeySpec] = [
        .init(fieldKey: "fullName", label: "Full name", kind: .text), .init(fieldKey: "address", label: "Address", kind: .text),
        .init(fieldKey: "postcode", label: "Postcode", kind: .text), .init(fieldKey: "phone", label: "Phone", kind: .text),
        .init(fieldKey: "email", label: "Email", kind: .text)]

    /// Document ordering in the keyboard: cards, passport, NRIC, China ID, then the rest.
    public static func order(_ t: DocumentType) -> Int {
        switch t { case .bankCard: 0; case .passport: 1; case .nric: 2; case .chinaID: 3; case .businessCard: 4; default: 9 }
    }
}
