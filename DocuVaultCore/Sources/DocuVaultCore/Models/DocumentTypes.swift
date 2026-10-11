import Foundation

/// Document types the app recognises. Display names are always English (per spec).
public enum DocumentType: String, Codable, CaseIterable, Sendable {
    case passport
    case nric            // Singapore NRIC / FIN
    case chinaID         // PRC 居民身份证
    case bankCard        // credit / debit card
    case receipt
    case contract
    case letter
    case businessCard
    case other

    public var displayName: String {
        switch self {
        case .passport: return "Passport"
        case .nric: return "NRIC / FIN"
        case .chinaID: return "China ID Card"
        case .bankCard: return "Bank Card"
        case .receipt: return "Receipt"
        case .contract: return "Contract"
        case .letter: return "Letter"
        case .businessCard: return "Business Card"
        case .other: return "Other"
        }
    }

    /// Sensitive types go to the Vault by default and never leave the device.
    public var isSensitiveByDefault: Bool {
        switch self {
        case .passport, .nric, .chinaID, .bankCard: return true
        default: return false
        }
    }
}

/// How a field value was verified. Drives the green / amber / red review colours.
public enum FieldCheck: String, Codable, Sendable {
    case mrz        // passport machine-readable zone check digit passed
    case luhn       // card number passed Luhn
    case nric       // Singapore NRIC/FIN checksum passed
    case cnid       // PRC ID 18-digit checksum passed
    case regex      // matched a strict pattern (dates, postcodes)
    case ocr        // read by OCR only, no independent check
    case user       // typed or edited by the user
    case missing    // not found

    public var confidenceTier: ConfidenceTier {
        switch self {
        case .mrz, .luhn, .nric, .cnid, .user: return .verified
        case .regex, .ocr: return .unverified
        case .missing: return .missing
        }
    }
}

public enum ConfidenceTier: String, Codable, Sendable {
    case verified    // green
    case unverified  // amber
    case missing     // red
}

/// Where a field is shown in the review screen and the .md file.
/// `secondary` holds race / ethnicity / blood group, kept apart from the main block (per spec).
public enum FieldSection: String, Codable, Sendable {
    case main
    case secondary
}

/// One extracted field. Value is a plain string; typed parsing happens at the call site.
public struct ExtractedField: Codable, Equatable, Sendable, Identifiable {
    public var id: String { key }
    public let key: String
    public let labelEN: String
    public let labelZH: String?
    public var value: String
    public var check: FieldCheck
    public var section: FieldSection
    public var ocrConfidence: Double?   // 0…1 from Vision, when available

    public init(key: String, labelEN: String, labelZH: String? = nil, value: String,
                check: FieldCheck, section: FieldSection = .main, ocrConfidence: Double? = nil) {
        self.key = key
        self.labelEN = labelEN
        self.labelZH = labelZH
        self.value = value
        self.check = check
        self.section = section
        self.ocrConfidence = ocrConfidence
    }
}

/// Owner categories. `client` groups get auto-expiry (default 30 days, warn at 3).
public enum PersonKind: String, Codable, CaseIterable, Sendable {
    case me, family, client, partner, other

    public var displayName: String {
        switch self {
        case .me: return "Me"
        case .family: return "Family"
        case .client: return "Client"
        case .partner: return "Business Partner"
        case .other: return "Other"
        }
    }

    public var defaultAutoExpireDays: Int? {
        self == .client ? 30 : nil
    }
}

public enum RetentionPolicy {
    public static let clientDefaultDays = 30
    public static let warnDaysBefore = 3
    public static let extensionDays = 30
}
