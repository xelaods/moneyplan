import Foundation

/// 取引の集計（アプリの画面とウィジェット用のまとめで共通）
struct Ledger {
    let txns: [Txn]
    let categories: [TxnCategory]
    let budget: Budget
    let now: Date

    init(file: LedgerFile, now: Date = Date()) {
        self.init(txns: file.txns, categories: file.categories, budget: file.budget, now: now)
    }

    init(txns: [Txn], categories: [TxnCategory], budget: Budget, now: Date = Date()) {
        self.txns = txns.sorted { $0.date > $1.date }
        self.categories = categories
        self.budget = budget
        self.now = now
    }

    var current: Period { Period(containing: now, startDay: budget.startDay) }

    func category(_ id: String) -> TxnCategory {
        categories.first { $0.id == id }
            ?? TxnCategory.defaults.first { $0.id == id }
            ?? TxnCategory.defaults.first { $0.id == TxnCategory.otherID }!
    }

    func txns(in period: Period) -> [Txn] {
        txns.filter { period.contains($0.date) }
    }

    func spent(in period: Period, through day: DayKey? = nil) -> Int {
        txns(in: period).filter { $0.kind == .expense && (day == nil || $0.day <= day!) }.reduce(0) { $0 + $1.amount }
    }

    func income(in period: Period) -> Int {
        txns(in: period).filter { $0.kind == .income }.reduce(0) { $0 + $1.amount }
    }

    func spent(on day: DayKey) -> Int {
        txns.filter { $0.kind == .expense && $0.day == day }.reduce(0) { $0 + $1.amount }
    }

    /// 費目ごとの支出（多い順）
    func byCategory(in period: Period, kind: TxnKind = .expense) -> [(category: TxnCategory, amount: Int)] {
        var sums: [String: Int] = [:]
        for t in txns(in: period) where t.kind == kind { sums[t.categoryID, default: 0] += t.amount }
        return sums.map { (category($0.key), $0.value) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.name < $1.0.name }
    }

    /// 期間の日ごとの支出
    func dailySpent(in period: Period) -> [Int] {
        var sums: [DayKey: Int] = [:]
        for t in txns(in: period) where t.kind == .expense { sums[t.day, default: 0] += t.amount }
        return period.days.map { sums[$0] ?? 0 }
    }

    /// 期間の始めからの累計（今日まで。未来の日は含めない）
    func cumulative(in period: Period) -> [Int] {
        let today = DayKey(now)
        var total = 0
        var out: [Int] = []
        for (day, v) in zip(period.days, dailySpent(in: period)) where day <= today {
            total += v
            out.append(total)
        }
        return out
    }

    // MARK: 予算のペース

    /// 今日が期間の何日目か（1から）
    var dayIndex: Int { min(current.numberOfDays, max(1, current.first.days(to: DayKey(now)) + 1)) }
    /// 今日を含めた残りの日数
    var daysLeft: Int { max(1, current.numberOfDays - dayIndex + 1) }

    var spentThisPeriod: Int { spent(in: current) }
    var spentToday: Int { spent(on: DayKey(now)) }
    var remaining: Int { budget.monthly - spentThisPeriod }

    /// 今日から使える1日あたりの額（今日使った分は今日の枠に含める）
    var dailyAllowance: Int {
        guard budget.monthly > 0 else { return 0 }
        let beforeToday = spentThisPeriod - spentToday
        return max(0, (budget.monthly - beforeToday) / daysLeft)
    }

    /// 予算どおりに使ったときの、今日までの目安
    var paceTarget: Int {
        guard budget.monthly > 0 else { return 0 }
        return Int(Double(budget.monthly) * Double(dayIndex) / Double(current.numberOfDays))
    }

    /// 前の期間の同じ日数までの支出（前月比のため）
    var lastPeriodSameDay: Int {
        let prev = current.adding(-1)
        let day = prev.first.adding(days: min(prev.numberOfDays, dayIndex) - 1)
        return spent(in: prev, through: day)
    }

    /// 期間の終わりの見込み（今のペースのまま使った場合）
    var projected: Int {
        let spent = spentThisPeriod
        guard dayIndex > 0 else { return spent }
        return Int(Double(spent) / Double(dayIndex) * Double(current.numberOfDays))
    }

    /// 支払い方法（カード・口座）ごとの支出
    func byAccount(in period: Period) -> [(account: String, amount: Int)] {
        var sums: [String: Int] = [:]
        for t in txns(in: period) where t.kind == .expense {
            sums[t.account.isEmpty ? "未設定" : t.account, default: 0] += t.amount
        }
        return sums.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }

    /// よく行くお店（回数の多い順）
    func topMerchants(in period: Period, limit: Int = 5) -> [(merchant: String, count: Int, amount: Int)] {
        var sums: [String: (Int, Int)] = [:]
        for t in txns(in: period) where t.kind == .expense && !t.merchant.isEmpty {
            let v = sums[t.merchant] ?? (0, 0)
            sums[t.merchant] = (v.0 + 1, v.1 + t.amount)
        }
        return sums.map { ($0.key, $0.value.0, $0.value.1) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 > $1.2 }
            .prefix(limit).map { $0 }
    }

    /// 最近の期間の支出（グラフ用。古い順）
    func history(periods n: Int) -> [(period: Period, spent: Int, income: Int)] {
        (0..<n).reversed().map { i in
            let p = current.adding(-i)
            return (p, spent(in: p), income(in: p))
        }
    }

    // MARK: ウィジェット用のまとめ

    func summary() -> WidgetSummary {
        let p = current
        let slices = byCategory(in: p).map { item in
            WidgetSummary.Slice(name: item.category.name, symbol: item.category.symbol,
                                light: item.category.lightHex, dark: item.category.darkHex, amount: item.amount)
        }
        let recent = txns.prefix(8).map { t -> WidgetSummary.Item in
            let c = category(t.categoryID)
            return WidgetSummary.Item(date: t.date, merchant: t.merchant.isEmpty ? c.name : t.merchant, amount: t.amount,
                                      income: t.kind == .income, symbol: c.symbol, light: c.lightHex, dark: c.darkHex)
        }
        return WidgetSummary(
            updatedAt: now,
            periodTitle: p.title,
            rangeLabel: p.rangeLabel,
            startDay: budget.startDay,
            periodStart: p.start,
            periodEnd: p.end,
            budget: budget.monthly,
            spent: spentThisPeriod,
            income: income(in: p),
            today: spentToday,
            todayKey: DayKey(now).id,
            lastPeriodSameDay: lastPeriodSameDay,
            cumulative: cumulative(in: p),
            days: p.numberOfDays,
            slices: Array(slices.prefix(6)),
            otherAmount: slices.dropFirst(6).reduce(0) { $0 + $1.amount },
            recent: Array(recent)
        )
    }
}

/// ウィジェットに渡す今月のまとめ（取引すべてではなく、表示に必要な分だけ）
struct WidgetSummary: Codable, Equatable {
    struct Slice: Codable, Equatable, Hashable {
        var name: String
        var symbol: String
        var light: UInt32
        var dark: UInt32
        var amount: Int
    }

    struct Item: Codable, Equatable, Hashable {
        var date: Date
        var merchant: String
        var amount: Int
        var income: Bool
        var symbol: String
        var light: UInt32
        var dark: UInt32
    }

    var updatedAt: Date
    var periodTitle: String
    var rangeLabel: String
    var startDay: Int
    var periodStart: Date
    var periodEnd: Date
    var budget: Int
    var spent: Int
    var income: Int
    var today: Int
    var todayKey: Int
    var lastPeriodSameDay: Int
    var cumulative: [Int]
    var days: Int
    var slices: [Slice]
    var otherAmount: Int
    var recent: [Item]

    /// 日付が変わった・期間が変わったときに、ウィジェット側で辻褄を合わせる
    func adjusted(for now: Date) -> WidgetSummary {
        var s = self
        if now >= periodEnd {
            // アプリを開くまでは新しい期間を 0 円として見せる
            let p = Period(containing: now, startDay: startDay)
            s.periodTitle = p.title
            s.rangeLabel = p.rangeLabel
            s.periodStart = p.start
            s.periodEnd = p.end
            s.spent = 0
            s.income = 0
            s.today = 0
            s.lastPeriodSameDay = 0
            s.cumulative = []
            s.days = p.numberOfDays
            s.slices = []
            s.otherAmount = 0
        } else if DayKey(now).id != todayKey {
            s.today = 0
        }
        return s
    }

    var remaining: Int { budget - spent }
    func dayIndex(at now: Date) -> Int {
        min(days, max(1, DayKey(periodStart).days(to: DayKey(now)) + 1))
    }

    func dailyAllowance(at now: Date) -> Int {
        guard budget > 0 else { return 0 }
        let left = max(1, days - dayIndex(at: now) + 1)
        return max(0, (budget - (spent - today)) / left)
    }

    func paceTarget(at now: Date) -> Int {
        guard budget > 0, days > 0 else { return 0 }
        return Int(Double(budget) * Double(dayIndex(at: now)) / Double(days))
    }
}
