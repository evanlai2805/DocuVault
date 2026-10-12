import Foundation

/// Expense categories modelled on Expensify / SAP Concur / QuickBooks defaults, trimmed for a personal + small-business user
/// in Singapore and China. Each carries keywords for the receipt extractor's guess.
public struct ExpenseCategory: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let group: String
    public let keywords: [String]   // upper-cased substrings matched against the receipt text
}

public enum ExpenseCategories {
    public static let all: [ExpenseCategory] = [
        // Travel
        .init(name: "Flights", group: "Travel", keywords: ["AIRLINES", "AIRWAYS", "AIR ASIA", "SCOOT", "JETSTAR", "BOARDING", "FLIGHT", "航空", "机票"]),
        .init(name: "Hotel", group: "Travel", keywords: ["HOTEL", "RESORT", "INN", "HOSTEL", "AIRBNB", "酒店", "宾馆", "住宿"]),
        .init(name: "Taxi & Ride-hail", group: "Travel", keywords: ["GRAB", "TAXI", "COMFORT", "GOJEK", "UBER", "滴滴", "出租车", "打车"]),
        .init(name: "Public Transport", group: "Travel", keywords: ["MRT", "SMRT", "SBS", "BUS", "EZ-LINK", "TRAIN", "RAIL", "地铁", "高铁", "火车", "12306"]),
        .init(name: "Parking & Tolls", group: "Travel", keywords: ["PARKING", "CARPARK", "ERP", "TOLL", "停车", "高速"]),
        .init(name: "Fuel", group: "Travel", keywords: ["SHELL", "ESSO", "CALTEX", "SPC", "PETROL", "SINOPEC", "加油"]),
        .init(name: "Travel · Other", group: "Travel", keywords: ["VISA FEE", "TRAVEL INSURANCE", "LOUNGE", "签证"]),
        // Food
        .init(name: "Meals · Business", group: "Food", keywords: ["RESTAURANT", "BISTRO", "DINING", "餐厅", "饭店", "商务宴请"]),
        .init(name: "Meals · Personal", group: "Food", keywords: ["CAFE", "COFFEE", "KOPITIAM", "HAWKER", "FOOD COURT", "MCDONALD", "KFC", "STARBUCKS", "咖啡", "快餐", "小吃"]),
        .init(name: "Groceries", group: "Food", keywords: ["NTUC", "FAIRPRICE", "COLD STORAGE", "SHENG SIONG", "GIANT", "DON DON DONKI", "SUPERMARKET", "超市", "永辉", "盒马"]),
        // Work
        .init(name: "Office Supplies", group: "Work", keywords: ["POPULAR", "STATIONERY", "PRINTING", "TONER", "PAPER", "文具", "打印"]),
        .init(name: "Software & Subscriptions", group: "Work", keywords: ["APPLE.COM", "GOOGLE", "MICROSOFT", "ADOBE", "OPENAI", "ANTHROPIC", "NOTION", "SUBSCRIPTION", "LICENSE", "SAAS", "订阅"]),
        .init(name: "Phone & Internet", group: "Work", keywords: ["SINGTEL", "STARHUB", "M1", "SIMBA", "CIRCLES", "BROADBAND", "DATA PLAN", "中国移动", "中国联通", "中国电信", "话费"]),
        .init(name: "Professional Services", group: "Work", keywords: ["LLP", "LAW", "LEGAL", "ACCOUNTING", "AUDIT", "CONSULTING", "NOTARY", "律师", "会计", "公证", "咨询"]),
        .init(name: "Courier & Postage", group: "Work", keywords: ["SINGPOST", "DHL", "FEDEX", "UPS", "NINJA VAN", "COURIER", "顺丰", "快递", "邮政"]),
        .init(name: "Education & Training", group: "Work", keywords: ["COURSE", "TRAINING", "UNIVERSITY", "NUS", "NTU", "SMU", "UDEMY", "COURSERA", "培训", "学费"]),
        // Personal
        .init(name: "Medical & Health", group: "Personal", keywords: ["CLINIC", "PHARMACY", "HOSPITAL", "GUARDIAN", "WATSONS", "UNITY", "DENTAL", "POLYCLINIC", "医院", "药店", "诊所"]),
        .init(name: "Insurance", group: "Personal", keywords: ["INSURANCE", "PREMIUM", "AIA", "PRUDENTIAL", "GREAT EASTERN", "NTUC INCOME", "保险"]),
        .init(name: "Utilities", group: "Personal", keywords: ["SP GROUP", "SP SERVICES", "ELECTRICITY", "WATER", "GAS", "电费", "水费", "燃气"]),
        .init(name: "Rent", group: "Personal", keywords: ["RENT", "RENTAL", "LEASE", "租金", "房租"]),
        .init(name: "Shopping", group: "Personal", keywords: ["SHOPEE", "LAZADA", "AMAZON", "TAOBAO", "JD.COM", "UNIQLO", "IKEA", "淘宝", "京东", "拼多多"]),
        .init(name: "Entertainment", group: "Personal", keywords: ["CINEMA", "GOLDEN VILLAGE", "SHAW", "CATHAY", "NETFLIX", "SPOTIFY", "CONCERT", "TICKET", "电影", "演出"]),
        .init(name: "Gifts & Donations", group: "Personal", keywords: ["GIFT", "DONATION", "CHARITY", "FLORIST", "礼品", "捐赠", "花店"]),
        .init(name: "Fees & Charges", group: "Personal", keywords: ["BANK FEE", "ANNUAL FEE", "LATE FEE", "SERVICE CHARGE", "ADMIN FEE", "手续费", "年费"]),
        .init(name: "Taxes & Government", group: "Personal", keywords: ["IRAS", "ICA", "LTA", "HDB", "CPF", "GOVERNMENT", "税务", "政府"]),
        .init(name: "Other", group: "Other", keywords: [])
    ]

    public static let names: [String] = all.map(\.name)

    /// Categories were renamed from "Travel — Other" to "Travel · Other" when em dashes left the UI.
    /// Receipts saved before that still carry the old string, so resolve both spellings to one category.
    public static func canonical(_ storedName: String) -> String {
        let dotted = storedName.replacingOccurrences(of: " — ", with: " · ")
        return names.contains(dotted) ? dotted : storedName
    }

    public static func category(named storedName: String) -> ExpenseCategory? {
        let n = canonical(storedName)
        return all.first { $0.name == n }
    }
    public static let groups: [String] = ["Travel", "Food", "Work", "Personal", "Other"]

    /// Best category for receipt text. First keyword hit in list order wins; "Other" when nothing matches.
    public static func guess(from text: String) -> String {
        let u = text.uppercased()
        for c in all where !c.keywords.isEmpty {
            if c.keywords.contains(where: { u.contains($0) }) { return c.name }
        }
        return "Other"
    }
}
