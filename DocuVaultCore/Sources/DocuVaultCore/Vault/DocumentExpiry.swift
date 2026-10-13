import Foundation

/// When a vault document joins the Vault's red attention card (checkpoint 16 Q5): a passport within
/// six months of expiry (the common entry rule abroad), an ID card or bank card within one month.
/// Computed from the stored expiry field, never guessed.
public enum DocumentExpiry {

    public enum Status: Equatable, Sendable {
        case none                     // no expiry stored, or outside the warning window
        case soon(daysLeft: Int)
        case expired
    }

    /// Field keys that hold an expiry, in the order they are tried.
    public static let keys = ["expiry", "validTo", "expiryDate"]

    /// Months before expiry that a document type starts warning; nil = never warns.
    public static func warningMonths(_ type: DocumentType) -> Int? {
        switch type {
        case .passport: 6
        case .nric, .chinaID, .bankCard: 1
        default: nil
        }
    }

    /// The last valid day. ISO yyyy-MM-dd for IDs and passports; MM/YY for bank cards, which are valid
    /// to the end of that month. Free text such as 长期 has no date.
    public static func date(type: DocumentType, fields: [String: String], calendar: Calendar = .dv) -> Date? {
        guard let raw = keys.lazy.compactMap({ fields[$0] }).first(where: { !$0.isEmpty }) else { return nil }
        if type == .bankCard {
            let parts = raw.split(separator: "/")
            guard parts.count == 2, let m = Int(parts[0]), let y = Int(parts[1]), (1...12).contains(m) else { return nil }
            let year = y < 100 ? 2000 + y : y
            guard let first = calendar.date(from: DateComponents(year: year, month: m, day: 1)),
                  let next = calendar.date(byAdding: .month, value: 1, to: first) else { return nil }
            return calendar.date(byAdding: .day, value: -1, to: next)
        }
        guard TextRules.firstISODate(in: raw) == raw else { return nil }
        let p = raw.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    public static func status(type: DocumentType, fields: [String: String], now: Date = Date(), calendar: Calendar = .dv) -> Status {
        guard let months = warningMonths(type), let expiry = date(type: type, fields: fields, calendar: calendar) else { return .none }
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: expiry)).day ?? 0
        if days < 0 { return .expired }
        guard let edge = calendar.date(byAdding: .month, value: months, to: today), expiry <= edge else { return .none }
        return .soon(daysLeft: days)
    }

    /// "Expires in 5 months", "Expires in 12 d", "Expires today", "Expired". Months from 60 days out.
    public static func phrase(_ status: Status, now: Date = Date(), calendar: Calendar = .dv) -> String? {
        switch status {
        case .none: return nil
        case .expired: return "Expired"
        case .soon(let d) where d == 0: return "Expires today"
        case .soon(let d) where d < 60: return "Expires in \(d) d"
        case .soon(let d): let m = d / 30; return "Expires in \(m) month\(m == 1 ? "" : "s")"
        }
    }
}

public extension Calendar {
    /// Gregorian in the phone's time zone; tests pass a fixed one.
    static var dv: Calendar { Calendar(identifier: .gregorian) }
}
