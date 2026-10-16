import Foundation

/// 入金か出金か
enum TxnKind: String, Codable, CaseIterable, Identifiable {
    case expense, income
    var id: String { rawValue }
    var label: String { self == .expense ? "支出" : "収入" }
}

/// どこから記録されたか
enum TxnSource: String, Codable, CaseIterable {
    /// ショートカットの「取引」オートメーション（Apple Pay）
    case applePay
    /// アプリで手入力
    case manual
    /// 銀行の入出金通知（メールなどを貼り付け）
    case bank
    /// CSV の読み込み
    case csv

    var label: String {
        switch self {
        case .applePay: return "Apple Pay"
        case .manual: return "手入力"
        case .bank: return "銀行"
        case .csv: return "CSV"
        }
    }

    var symbol: String {
        switch self {
        case .applePay: return "wave.3.right"
        case .manual: return "pencil"
        case .bank: return "building.columns"
        case .csv: return "tablecells"
        }
    }
}

/// 1件の取引。金額は円の整数で持つ（常に正の数。向きは kind で表す）
struct Txn: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var date: Date
    var amount: Int
    var kind: TxnKind = .expense
    var merchant: String
    var categoryID: String
    var account: String = ""
    var note: String = ""
    var source: TxnSource = .manual

    /// 支出ならマイナス、収入ならプラス
    var signed: Int { kind == .expense ? -amount : amount }
    var day: DayKey { DayKey(date) }
    /// 金額が届かなかった記録（あとで入力する）
    var needsAmount: Bool { amount == 0 }

    init(id: UUID = UUID(), date: Date, amount: Int, kind: TxnKind = .expense, merchant: String,
         categoryID: String, account: String = "", note: String = "", source: TxnSource = .manual) {
        self.id = id
        self.date = date
        self.amount = amount
        self.kind = kind
        self.merchant = merchant
        self.categoryID = categoryID
        self.account = account
        self.note = note
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try c.decode(Date.self, forKey: .date)
        amount = try c.decode(Int.self, forKey: .amount)
        kind = try c.decodeIfPresent(TxnKind.self, forKey: .kind) ?? .expense
        merchant = try c.decodeIfPresent(String.self, forKey: .merchant) ?? ""
        categoryID = try c.decodeIfPresent(String.self, forKey: .categoryID) ?? TxnCategory.otherID
        account = try c.decodeIfPresent(String.self, forKey: .account) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        source = try c.decodeIfPresent(TxnSource.self, forKey: .source) ?? .manual
    }
}

/// 費目。色は16進数で持つ（ウィジェットでも同じ色を使うため）
struct TxnCategory: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var name: String
    var symbol: String
    var lightHex: UInt32
    var darkHex: UInt32
    var kind: TxnKind = .expense

    static let otherID = "other"
    static let otherIncomeID = "income-other"

    static let defaults: [TxnCategory] = [
        TxnCategory(id: "food", name: "食費", symbol: "fork.knife", lightHex: 0xE0602C, darkHex: 0xF5804F),
        TxnCategory(id: "cafe", name: "カフェ・おやつ", symbol: "cup.and.saucer.fill", lightHex: 0xA0662F, darkHex: 0xD49A63),
        TxnCategory(id: "daily", name: "日用品", symbol: "basket.fill", lightHex: 0x2E9C8F, darkHex: 0x4FCDBE),
        TxnCategory(id: "transport", name: "交通", symbol: "tram.fill", lightHex: 0x2F64D6, darkHex: 0x6C95F2),
        TxnCategory(id: "hobby", name: "趣味・娯楽", symbol: "gamecontroller.fill", lightHex: 0x8A4FD0, darkHex: 0xB28AF5),
        TxnCategory(id: "fashion", name: "服・美容", symbol: "tshirt.fill", lightHex: 0xD0428A, darkHex: 0xF27AB4),
        TxnCategory(id: "subscription", name: "サブスク・通信", symbol: "arrow.triangle.2.circlepath", lightHex: 0x4C50D0, darkHex: 0x8A8EF7),
        TxnCategory(id: "study", name: "学び・本", symbol: "book.closed.fill", lightHex: 0x1E8A5A, darkHex: 0x3DBB78),
        TxnCategory(id: "health", name: "医療・ジム", symbol: "cross.case.fill", lightHex: 0xC93A3A, darkHex: 0xF06A6A),
        TxnCategory(id: "social", name: "交際費", symbol: "person.2.fill", lightHex: 0xD98A0B, darkHex: 0xF2B53C),
        TxnCategory(id: "living", name: "住まい・光熱", symbol: "house.fill", lightHex: 0x5D6B78, darkHex: 0x9AA8B5),
        TxnCategory(id: otherID, name: "その他", symbol: "square.grid.2x2.fill", lightHex: 0x7A7D83, darkHex: 0x9A9DA3),
        TxnCategory(id: "salary", name: "給与", symbol: "yensign.circle.fill", lightHex: 0x1E8A5A, darkHex: 0x3DBB78, kind: .income),
        TxnCategory(id: "allowance", name: "仕送り・お小遣い", symbol: "gift.fill", lightHex: 0x2E9C8F, darkHex: 0x4FCDBE, kind: .income),
        TxnCategory(id: otherIncomeID, name: "その他の収入", symbol: "plus.circle.fill", lightHex: 0x5D6B78, darkHex: 0x9AA8B5, kind: .income)
    ]
}

/// 予算や締め日などの設定
struct Budget: Codable, Equatable {
    /// 1か月の予算（0なら予算なし）
    var monthly: Int = 60000
    /// 費目ごとの予算（費目ID → 円）
    var byCategory: [String: Int] = [:]
    /// 月の始まりの日（1なら毎月1日〜末日。25なら25日〜翌月24日）
    var startDay: Int = 1

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        monthly = try c.decodeIfPresent(Int.self, forKey: .monthly) ?? 60000
        byCategory = try c.decodeIfPresent([String: Int].self, forKey: .byCategory) ?? [:]
        startDay = min(28, max(1, try c.decodeIfPresent(Int.self, forKey: .startDay) ?? 1))
    }
}

/// 保存するデータ全体
struct LedgerFile: Codable {
    var version = 1
    var txns: [Txn] = []
    var categories: [TxnCategory] = TxnCategory.defaults
    var budget = Budget()
    /// 店名 → 費目（直したときに覚える）
    var learned: [String: String] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        txns = try c.decodeIfPresent([Txn].self, forKey: .txns) ?? []
        let saved = try c.decodeIfPresent([TxnCategory].self, forKey: .categories) ?? []
        // 後から増えた標準の費目も足す
        var merged = saved
        for d in TxnCategory.defaults where !merged.contains(where: { $0.id == d.id }) { merged.append(d) }
        categories = merged.isEmpty ? TxnCategory.defaults : merged
        budget = try c.decodeIfPresent(Budget.self, forKey: .budget) ?? Budget()
        learned = try c.decodeIfPresent([String: String].self, forKey: .learned) ?? [:]
    }
}

/// 家計簿の「月」。月の始まりの日が1以外のときは前月の途中から始まる
struct Period: Hashable, Comparable, Identifiable {
    /// 期間の名前になる月（25日始まりなら、10/25〜11/24 は「11月」）
    let month: MonthKey
    let startDay: Int

    init(month: MonthKey, startDay: Int) {
        self.month = month
        self.startDay = min(28, max(1, startDay))
    }

    init(containing date: Date, startDay: Int) {
        let d = DayKey(date)
        let s = min(28, max(1, startDay))
        if s == 1 || d.day < s {
            self.init(month: d.monthKey, startDay: s)
        } else {
            self.init(month: d.monthKey.adding(months: 1), startDay: s)
        }
    }

    var id: Int { month.id }

    var first: DayKey {
        startDay == 1 ? month.firstDay : DayKey(year: month.adding(months: -1).year, month: month.adding(months: -1).month, day: startDay)
    }

    var last: DayKey {
        startDay == 1 ? month.lastDay : DayKey(year: month.year, month: month.month, day: startDay - 1)
    }

    var start: Date { first.date }
    var end: Date { last.adding(days: 1).date }
    var numberOfDays: Int { first.days(to: last) + 1 }
    var days: [DayKey] { (0..<numberOfDays).map { first.adding(days: $0) } }

    func contains(_ date: Date) -> Bool { date >= start && date < end }
    func adding(_ n: Int) -> Period { Period(month: month.adding(months: n), startDay: startDay) }

    var title: String { "\(month.year)年\(month.month)月" }
    var shortTitle: String { "\(month.month)月" }
    var rangeLabel: String {
        "\(first.month)/\(first.day)〜\(last.month)/\(last.day)"
    }

    static func < (a: Period, b: Period) -> Bool { a.month < b.month }
}
