import Foundation

/// 日付はすべて日本時間で扱う
enum JST {
    static let timeZone = TimeZone(identifier: "Asia/Tokyo")!
    static let offset: TimeInterval = 9 * 3600

    static func calendar(firstWeekday: Int = 1) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        c.locale = Locale(identifier: "ja_JP")
        c.firstWeekday = firstWeekday
        return c
    }

    static let gregorian = calendar()
}

/// 1日を表すキー（日本時間）
struct DayKey: Hashable, Comparable, Identifiable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date) {
        let c = JST.gregorian.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 2000, month: c.month ?? 1, day: c.day ?? 1)
    }

    var id: Int { year * 10000 + month * 100 + day }
    /// その日の0時（日本時間）
    var date: Date { JST.gregorian.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0) }
    /// 1 = 日曜 … 7 = 土曜
    var weekday: Int { JST.gregorian.component(.weekday, from: date) }
    var monthKey: MonthKey { MonthKey(year: year, month: month) }

    func adding(days n: Int) -> DayKey {
        DayKey(JST.gregorian.date(byAdding: .day, value: n, to: date) ?? date)
    }

    func startOfWeek(firstWeekday: Int) -> DayKey {
        adding(days: -((weekday - firstWeekday + 7) % 7))
    }

    /// self から other までの日数
    func days(to other: DayKey) -> Int {
        Int(((other.date.timeIntervalSince(date)) / 86400).rounded())
    }

    static func < (a: DayKey, b: DayKey) -> Bool { a.id < b.id }
}

struct MonthKey: Hashable, Comparable, Identifiable {
    let year: Int
    let month: Int

    /// 月が1〜12の外でも年をまたいで正しく直す
    init(year: Int, month: Int) {
        let index = year * 12 + (month - 1)
        self.year = Int((Double(index) / 12).rounded(.down))
        self.month = index - self.year * 12 + 1
    }

    init(_ date: Date) {
        let d = DayKey(date)
        self.init(year: d.year, month: d.month)
    }

    var id: Int { year * 100 + month }
    var firstDay: DayKey { DayKey(year: year, month: month, day: 1) }
    var numberOfDays: Int { JST.gregorian.range(of: .day, in: .month, for: firstDay.date)?.count ?? 30 }
    var lastDay: DayKey { DayKey(year: year, month: month, day: numberOfDays) }

    func adding(months n: Int) -> MonthKey { MonthKey(year: year, month: month + n) }

    /// カレンダー表示用の週ごとの日付（前後の月の日も含む）
    func weeks(firstWeekday: Int) -> [[DayKey]] {
        var rows: [[DayKey]] = []
        var start = firstDay.startOfWeek(firstWeekday: firstWeekday)
        while start <= lastDay {
            let s = start
            rows.append((0..<7).map { s.adding(days: $0) })
            start = start.adding(days: 7)
        }
        return rows
    }

    static func < (a: MonthKey, b: MonthKey) -> Bool { a.id < b.id }
}
