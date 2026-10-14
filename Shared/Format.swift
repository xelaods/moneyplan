import Foundation

enum Fmt {
    private static let decimal: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "ja_JP")
        f.maximumFractionDigits = 0
        return f
    }()

    private static let decimal1: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "ja_JP")
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 1
        return f
    }()

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.timeZone = JST.timeZone
        f.dateFormat = format
        return f
    }

    private static let timeFormatter = formatter("H:mm")
    private static let monthDayFormatter = formatter("M/d")
    private static let weekdayFormatter = formatter("E")
    private static let fullFormatter = formatter("yyyy/MM/dd")

    /// 12,345
    static func number(_ value: Int) -> String {
        decimal.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// ¥12,345（マイナスは −¥12,345）
    static func yen(_ value: Int) -> String {
        (value < 0 ? "−¥" : "¥") + number(abs(value))
    }

    static func signedYen(_ value: Int) -> String {
        (value >= 0 ? "+¥" : "−¥") + number(abs(value))
    }

    /// 1.2万（1万未満はそのまま）
    static func short(_ value: Int) -> String {
        let a = abs(value)
        let sign = value < 0 ? "−" : ""
        if a < 10000 { return sign + number(a) }
        let v = (Double(a) / 1000).rounded(.down) / 10
        return sign + (decimal1.string(from: NSNumber(value: v)) ?? "0") + "万"
    }

    static func time(_ date: Date) -> String { timeFormatter.string(from: date) }
    static func monthDay(_ date: Date) -> String { monthDayFormatter.string(from: date) }
    static func weekday(_ date: Date) -> String { weekdayFormatter.string(from: date) }
    static func full(_ date: Date) -> String { fullFormatter.string(from: date) }
    /// 10/14（水）
    static func dayWithWeekday(_ date: Date) -> String { "\(monthDay(date))（\(weekday(date))）" }

    static func weekdaySymbol(_ weekday: Int) -> String {
        ["日", "月", "火", "水", "木", "金", "土"][(weekday - 1 + 7) % 7]
    }

    /// 今日・昨日・10/12（日）
    static func relativeDay(_ date: Date, now: Date) -> String {
        let n = DayKey(date).days(to: DayKey(now))
        switch n {
        case 0: return "今日"
        case 1: return "昨日"
        case 2: return "おととい"
        default: return dayWithWeekday(date)
        }
    }

    /// 「今日 12:30」「昨日 8:05」「10/12 19:40」
    static func when(_ date: Date, now: Date) -> String {
        let n = DayKey(date).days(to: DayKey(now))
        switch n {
        case 0: return "今日 \(time(date))"
        case 1: return "昨日 \(time(date))"
        default: return "\(monthDay(date)) \(time(date))"
        }
    }
}
