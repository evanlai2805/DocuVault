import Foundation

/// Picks the date / expiry format a form most likely wants, from what iOS exposes to a keyboard.
/// Inputs are plain values so the rules can be tested without UIKit.
public enum FillInference {

    public enum FieldKeyboard: Sendable { case numeric, other }

    /// What to insert for a date field.
    public enum DatePlan: Equatable, Sendable {
        case full(FillFormats.DateStyle)
        case component(DateComponent)     // the field wants only the day, month or year
    }
    public enum DateComponent: Equatable, Sendable { case day, month, year }

    public struct Context: Sendable {
        public var keyboard: FieldKeyboard
        public var contentType: String?        // UITextContentType.rawValue, e.g. "birthdate", "birthdateDay", "creditCardExpiration"
        public var before: String              // text before the cursor in the field
        public var after: String               // text after the cursor
        public var region: String              // Locale region code, e.g. "SG", "CN", "US"
        public init(keyboard: FieldKeyboard = .other, contentType: String? = nil, before: String = "", after: String = "", region: String = "SG") {
            self.keyboard = keyboard; self.contentType = contentType; self.before = before; self.after = after; self.region = region
        }
    }

    /// Why the choice was made; the keyboard shows it as the key hint.
    public struct Choice<T: Equatable & Sendable>: Equatable, Sendable {
        public let value: T
        public let reason: String
    }

    // MARK: Dates

    public static func date(_ c: Context) -> Choice<DatePlan> {
        if let ct = c.contentType?.lowercased() {
            if ct.contains("birthdateday") { return .init(value: .component(.day), reason: "day field") }
            if ct.contains("birthdatemonth") { return .init(value: .component(.month), reason: "month field") }
            if ct.contains("birthdateyear") { return .init(value: .component(.year), reason: "year field") }
        }
        let nearby = (c.before.suffix(12) + c.after.prefix(12))
        if c.keyboard == .numeric {
            // Digits-only field. A region that writes year first gets YYYYMMDD; everyone else DDMMYYYY.
            return yearFirst(c.region) ? .init(value: .full(.digitsYMD), reason: "number pad") : .init(value: .full(.digitsDMY), reason: "number pad")
        }
        if nearby.contains("-") && !nearby.contains("/") { return .init(value: .full(.iso), reason: "dashes in field") }
        if nearby.contains("/") {
            return yearFirst(c.region) || c.region == "US" ? .init(value: .full(c.region == "US" ? .mdySlash : .iso), reason: "slashes in field")
                                                           : .init(value: .full(.dmySlash), reason: "slashes in field")
        }
        if let hint = formatHint(in: nearby) { return .init(value: .full(hint), reason: "format hint") }
        // Nothing to go on: region default. SG/MY/UK/HK → DD/MM/YYYY, CN/JP/KR → ISO, US → MM/DD/YYYY.
        switch c.region {
        case "US": return .init(value: .full(.mdySlash), reason: "US region")
        case "CN", "JP", "KR", "TW": return .init(value: .full(.iso), reason: "\(c.region) region")
        default: return .init(value: .full(.dmySlash), reason: "\(c.region) region")
        }
    }

    /// Recognise a literal format hint typed near the cursor, e.g. a placeholder the form echoed into the field.
    static func formatHint(in text: String) -> FillFormats.DateStyle? {
        let u = text.uppercased()
        if u.contains("YYYY-MM-DD") { return .iso }
        if u.contains("DD/MM/YYYY") { return .dmySlash }
        if u.contains("MM/DD/YYYY") { return .mdySlash }
        if u.contains("DDMMYYYY") { return .digitsDMY }
        if u.contains("YYYYMMDD") { return .digitsYMD }
        return nil
    }

    static func yearFirst(_ region: String) -> Bool { ["CN", "JP", "KR", "TW", "HU", "LT"].contains(region) }

    /// Insert only one component of an ISO date.
    public static func component(_ comp: DateComponent, of iso: String) -> String {
        let parts = iso.split(separator: "-").map(String.init)
        guard parts.count == 3 else { return iso }
        switch comp { case .day: return parts[2]; case .month: return parts[1]; case .year: return parts[0] }
    }

    // MARK: Card expiry

    public static func expiry(_ c: Context) -> Choice<FillFormats.ExpiryStyle> {
        if c.keyboard == .numeric { return .init(value: .mmyy, reason: "number pad") }
        let nearby = (c.before.suffix(8) + c.after.prefix(8)).uppercased()
        if nearby.contains("YYYY") { return .init(value: .mmSlashYYYY, reason: "4-digit year hint") }
        return .init(value: .mmSlashYY, reason: "default")
    }

    // MARK: Card number

    /// Spaces only when the field already contains spaced groups (rare); digits otherwise.
    public static func cardSpaced(_ c: Context) -> Bool {
        c.keyboard != .numeric && c.before.range(of: #"\d{4} \d{1,4}"#, options: .regularExpression) != nil
    }
}
