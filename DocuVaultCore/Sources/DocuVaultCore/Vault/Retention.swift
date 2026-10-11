import Foundation

/// Client-document retention. Defaults: 30 days, warn 3 days before, extend by 30, keep indefinitely, or delete now.
public enum Retention {

    public enum Status: Equatable, Sendable {
        case none                    // no expiry (me, family, partner, or kept indefinitely)
        case active(daysLeft: Int)   // more than `warnDaysBefore` days left
        case warning(daysLeft: Int)  // within the warning window
        case due                     // expiry passed → delete on next sweep
    }

    public enum Action: String, CaseIterable, Sendable {
        case extend = "Extend 30 days"
        case keep = "Keep indefinitely"
        case deleteNow = "Delete now"
    }

    /// Expiry date for a document captured at `capturedAt` under `retentionDays` (nil → no expiry).
    public static func expiryDate(capturedAt: Date, retentionDays: Int?) -> Date? {
        guard let d = retentionDays else { return nil }
        return Calendar(identifier: .gregorian).date(byAdding: .day, value: d, to: capturedAt)
    }

    public static func status(expiresAt: Date?, now: Date = Date()) -> Status {
        guard let e = expiresAt else { return .none }
        let days = daysBetween(now, e)
        if days < 0 { return .due }
        if days <= RetentionPolicy.warnDaysBefore { return .warning(daysLeft: days) }
        return .active(daysLeft: days)
    }

    /// Apply a user action. Returns the new expiry (nil = keep forever). `.deleteNow` returns `.delete`.
    public enum Outcome: Equatable, Sendable { case newExpiry(Date?), delete }
    public static func apply(_ action: Action, currentExpiry: Date?, now: Date = Date()) -> Outcome {
        switch action {
        case .extend:
            let base = max(currentExpiry ?? now, now)
            return .newExpiry(Calendar(identifier: .gregorian).date(byAdding: .day, value: RetentionPolicy.extensionDays, to: base))
        case .keep: return .newExpiry(nil)
        case .deleteNow: return .delete
        }
    }

    /// Tombstone line kept in index.md after an auto-delete (Evan: keep a one-line trace).
    public static func tombstoneLine(title: String, type: DocumentType, owner: String, deletedAt: Date, retentionDays: Int) -> String {
        "- ~~\(title)~~ · \(type.displayName) · \(owner) · deleted \(isoDay(deletedAt)) after \(retentionDays) d"
    }

    static func daysBetween(_ a: Date, _ b: Date) -> Int {
        let cal = Calendar(identifier: .gregorian)
        return cal.dateComponents([.day], from: cal.startOfDay(for: a), to: cal.startOfDay(for: b)).day ?? 0
    }

    static func isoDay(_ d: Date) -> String {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }
}
