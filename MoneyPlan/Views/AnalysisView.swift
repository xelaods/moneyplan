import SwiftUI
import Charts

/// 分析：費目の割合、日ごとの支出、月ごとの推移、よく使うお店と支払い方法
struct AnalysisView: View {
    @EnvironmentObject var store: Store
    @State private var period: Period?
    @State private var direction: CGFloat = 1
    @State private var kind: TxnKind = .expense
    @State private var selectedCategory: String?

    var body: some View {
        let l = store.ledger
        let current = l.current
        let p = period ?? current
        let binding = Binding<Period>(get: { period ?? current }, set: { period = $0; selectedCategory = nil })

        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    PeriodSwitcher(period: binding, direction: $direction, current: current)
                        .padding(.top, 4)

                    Picker("", selection: $kind) {
                        ForEach(TxnKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Group {
                        BreakdownCard(ledger: l, period: p, kind: kind, selected: $selectedCategory)
                        if kind == .expense {
                            DailyCard(ledger: l, period: p)
                            CategoryBudgetCard(ledger: l, period: p)
                            MerchantCard(ledger: l, period: p)
                            AccountCard(ledger: l, period: p)
                        }
                    }
                    .id(p.id * 10 + (kind == .expense ? 0 : 1))
                    .transition(.cinematicSlide(direction))

                    HistoryCard(ledger: l)

                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 16)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("分析")
            .animation(Motion.cinematicFast, value: p)
            .animation(Motion.cinematicFast, value: kind)
        }
    }
}

/// ドーナツと費目の一覧
struct BreakdownCard: View {
    let ledger: Ledger
    let period: Period
    let kind: TxnKind
    @Binding var selected: String?

    var body: some View {
        let items = ledger.byCategory(in: period, kind: kind)
        let total = items.reduce(0) { $0 + $1.amount }
        let focus = items.first { $0.category.id == selected }
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel(text: kind == .expense ? "支出の内訳" : "収入の内訳")
            if items.isEmpty {
                EmptyNote(symbol: "chart.pie", title: "記録がありません", message: "この期間の\(kind.label)はまだありません")
            } else {
                HStack(spacing: 18) {
                    ZStack {
                        Donut(parts: items.map { ($0.category.color.opacity(selected == nil || selected == $0.category.id ? 1 : 0.25), $0.amount) },
                              lineWidth: 18)
                        VStack(spacing: 2) {
                            Text(focus?.category.name ?? "合計")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                            Text(Fmt.short(focus?.amount ?? total))
                                .font(Theme.number(22, weight: .black))
                                .foregroundStyle(Theme.ink)
                                .contentTransition(.numericText())
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .padding(.horizontal, 22)
                    }
                    .frame(width: 140, height: 140)
                    .animation(Motion.snappy, value: selected)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(items.prefix(5), id: \.category.id) { item in
                            HStack(spacing: 6) {
                                Circle().fill(item.category.color).frame(width: 8, height: 8)
                                Text(item.category.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text("\(percent(item.amount, total))%")
                                    .font(Theme.number(13, weight: .bold))
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }

                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.category.id) { i, item in
                        if i > 0 { Divider().overlay(Theme.line).padding(.leading, 46) }
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            selected = selected == item.category.id ? nil : item.category.id
                        } label: {
                            VStack(spacing: 6) {
                                HStack(spacing: 10) {
                                    CategoryBadge(symbol: item.category.symbol, color: item.category.color, size: 34)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.category.name)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(Theme.ink)
                                        Text("\(count(item.category.id))件 · \(percent(item.amount, total))%")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                    Text(Fmt.yen(item.amount))
                                        .font(Theme.number(18, weight: .bold))
                                        .foregroundStyle(Theme.ink)
                                        .monospacedDigit()
                                }
                                if selected == item.category.id {
                                    VStack(spacing: 6) {
                                        ForEach(ledger.txns(in: period).filter { $0.categoryID == item.category.id && $0.kind == kind }.prefix(8)) { t in
                                            HStack {
                                                Text(Fmt.monthDay(t.date))
                                                    .font(Theme.number(13, weight: .semibold))
                                                    .foregroundStyle(Theme.muted)
                                                    .frame(width: 40, alignment: .leading)
                                                Text(t.merchant.isEmpty ? "—" : t.merchant)
                                                    .font(.system(size: 13))
                                                    .foregroundStyle(Theme.ink)
                                                    .lineLimit(1)
                                                Spacer()
                                                Text(Fmt.yen(t.amount))
                                                    .font(Theme.number(14, weight: .semibold))
                                                    .foregroundStyle(Theme.ink)
                                            }
                                        }
                                    }
                                    .padding(.leading, 44)
                                    .padding(.top, 4)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .animation(Motion.snappy, value: selected)
            }
        }
        .card(padding: 18)
    }

    private func percent(_ v: Int, _ total: Int) -> Int {
        total > 0 ? Int((Double(v) / Double(total) * 100).rounded()) : 0
    }

    private func count(_ id: String) -> Int {
        ledger.txns(in: period).filter { $0.categoryID == id && $0.kind == kind }.count
    }
}

/// 日ごとの支出（棒）と1日の平均
struct DailyCard: View {
    let ledger: Ledger
    let period: Period

    var body: some View {
        let values = ledger.dailySpent(in: period)
        let days = period.days
        let today = DayKey(ledger.now)
        let elapsed = max(1, days.filter { $0 <= today }.count)
        let avg = values.prefix(elapsed).reduce(0, +) / elapsed
        let maxDay = zip(days, values).max { $0.1 < $1.1 }
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: "日ごとの支出")
                Spacer()
                Text("1日平均 \(Fmt.yen(avg))")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }
            Chart {
                ForEach(Array(zip(days, values)), id: \.0) { day, v in
                    BarMark(x: .value("日", day.date, unit: .day), y: .value("円", v))
                        .foregroundStyle(day == today ? Theme.accent : Theme.ink.opacity(day > today ? 0.08 : 0.55))
                        .cornerRadius(2.5)
                }
                if avg > 0 {
                    RuleMark(y: .value("平均", avg))
                        .foregroundStyle(Theme.income)
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day(), centered: false)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    AxisGridLine().foregroundStyle(Theme.line)
                    AxisValueLabel {
                        if let v = value.as(Int.self) { Text(Fmt.short(v)) }
                    }
                }
            }
            .environment(\.timeZone, JST.timeZone)
            .frame(height: 160)
            if let m = maxDay, m.1 > 0 {
                Text("いちばん使った日：\(Fmt.dayWithWeekday(m.0.date)) \(Fmt.yen(m.1))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
        }
        .card(padding: 18)
    }
}

/// 費目ごとの予算（設定した費目だけ）
struct CategoryBudgetCard: View {
    let ledger: Ledger
    let period: Period

    var body: some View {
        let budgets = ledger.budget.byCategory.filter { $0.value > 0 }
        if !budgets.isEmpty {
            let spent = Dictionary(uniqueKeysWithValues: ledger.byCategory(in: period).map { ($0.category.id, $0.amount) })
            let target = period == ledger.current ? Double(ledger.dayIndex) / Double(period.numberOfDays) : 1
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(text: "費目ごとの予算")
                ForEach(budgets.sorted { $0.key < $1.key }, id: \.key) { id, budget in
                    let c = ledger.category(id)
                    let s = spent[id] ?? 0
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: c.symbol).foregroundStyle(c.color)
                            Text(c.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                            Spacer()
                            Text("\(Fmt.yen(s)) / \(Fmt.yen(budget))")
                                .font(Theme.number(15, weight: .bold))
                                .foregroundStyle(s > budget ? Theme.accent : Theme.ink)
                        }
                        BudgetBar(spent: s, budget: budget, target: Int(Double(budget) * target), height: 8)
                    }
                }
            }
            .card(padding: 18)
        }
    }
}

/// よく使うお店
struct MerchantCard: View {
    let ledger: Ledger
    let period: Period

    var body: some View {
        let items = ledger.topMerchants(in: period)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "よく使うお店")
                ForEach(Array(items.enumerated()), id: \.offset) { i, m in
                    HStack(spacing: 12) {
                        Text("\(i + 1)")
                            .font(Theme.number(18, weight: .black))
                            .foregroundStyle(i == 0 ? Theme.accent : Theme.faint)
                            .frame(width: 18)
                        Text(m.merchant)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Spacer()
                        Text("\(m.count)回")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                        Text(Fmt.yen(m.amount))
                            .font(Theme.number(16, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .frame(minWidth: 70, alignment: .trailing)
                    }
                }
            }
            .card(padding: 18)
        }
    }
}

/// 支払い方法ごと
struct AccountCard: View {
    let ledger: Ledger
    let period: Period

    var body: some View {
        let items = ledger.byAccount(in: period)
        if items.count > 1 || (items.first.map { $0.account != "未設定" } ?? false) {
            let total = max(1, items.reduce(0) { $0 + $1.amount })
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "支払い方法")
                ForEach(items, id: \.account) { a in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Image(systemName: a.account.lowercased().contains("pay") ? "wave.3.right" : "creditcard")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Theme.muted)
                            Text(a.account)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text(Fmt.yen(a.amount))
                                .font(Theme.number(16, weight: .bold))
                                .foregroundStyle(Theme.ink)
                        }
                        GeometryReader { g in
                            Capsule().fill(Theme.fill)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(Theme.ink.opacity(0.7))
                                        .frame(width: g.size.width * CGFloat(a.amount) / CGFloat(total))
                                }
                        }
                        .frame(height: 6)
                    }
                }
            }
            .card(padding: 18)
        }
    }
}

/// 月ごとの推移（6か月）
struct HistoryCard: View {
    let ledger: Ledger

    var body: some View {
        let history = ledger.history(periods: 6)
        let avg = history.dropLast().map(\.spent).filter { $0 > 0 }
        let mean = avg.isEmpty ? 0 : avg.reduce(0, +) / avg.count
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: "月ごとの推移")
                Spacer()
                if mean > 0 {
                    Text("過去の平均 \(Fmt.yen(mean))")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.ink)
                }
            }
            Chart {
                ForEach(history, id: \.period.id) { h in
                    BarMark(x: .value("月", h.period.shortTitle), y: .value("円", h.spent))
                        .foregroundStyle(by: .value("種類", "支出"))
                        .position(by: .value("種類", "支出"))
                        .cornerRadius(3)
                    BarMark(x: .value("月", h.period.shortTitle), y: .value("円", h.income))
                        .foregroundStyle(by: .value("種類", "収入"))
                        .position(by: .value("種類", "収入"))
                        .cornerRadius(3)
                }
                if ledger.budget.monthly > 0 {
                    RuleMark(y: .value("予算", ledger.budget.monthly))
                        .foregroundStyle(Theme.faint)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("予算").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.muted)
                        }
                }
            }
            .chartForegroundStyleScale(["支出": Theme.accent, "収入": Theme.income])
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    AxisGridLine().foregroundStyle(Theme.line)
                    AxisValueLabel {
                        if let v = value.as(Int.self) { Text(Fmt.short(v)) }
                    }
                }
            }
            .chartLegend(position: .top, alignment: .trailing)
            .frame(height: 190)
        }
        .card(padding: 18)
    }
}
