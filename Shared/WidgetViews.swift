import SwiftUI
import WidgetKit

// アプリ（見本の画面）とウィジェットで共通の表示。データは WidgetSummary だけを使う

// MARK: - 今月の支出

struct MonthWidgetView: View {
    let summary: WidgetSummary
    let now: Date
    let family: WidgetFamily

    private var s: WidgetSummary { summary }
    private var target: Int { s.paceTarget(at: now) }
    private var over: Bool { s.budget > 0 && s.remaining < 0 }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(s.budget > 0 ? "\(monthTitle) \(Fmt.yen(s.spent)) · 残り\(Fmt.short(s.remaining))" : "\(monthTitle) \(Fmt.yen(s.spent))")
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        case .systemMedium:
            medium
        default:
            small
        }
    }

    private var monthTitle: String {
        s.periodTitle.components(separatedBy: "年").last ?? s.periodTitle
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(monthTitle)
                    .font(.system(size: 12, weight: .heavy).width(.condensed))
                    .foregroundStyle(Theme.accent)
                Text("使ったお金")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 4)
            Amount(value: s.spent, size: 32)
            Spacer(minLength: 6)
            if s.budget > 0 {
                BudgetBar(spent: s.spent, budget: s.budget, target: target, height: 7)
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(over ? "オーバー" : "残り")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.muted)
                        Text(Fmt.yen(abs(s.remaining)))
                            .font(Theme.number(15, weight: .bold))
                            .foregroundStyle(over ? Theme.accent : Theme.ink)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("1日あたり")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.muted)
                        Text(Fmt.yen(s.dailyAllowance(at: now)))
                            .font(Theme.number(15, weight: .bold))
                            .foregroundStyle(Theme.income)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            } else {
                Text("今日 \(Fmt.yen(s.today))")
                    .font(Theme.number(15, weight: .bold))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private var medium: some View {
        HStack(spacing: 16) {
            small
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("今日")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.muted)
                    Text(Fmt.yen(s.today))
                        .font(Theme.number(15, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 0)
                    Link(destination: URL(string: "moneyplan://add")!) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(Theme.onAccent)
                            .frame(width: 26, height: 26)
                            .background(Theme.accent, in: Circle())
                    }
                }
                PaceChart(cumulative: s.cumulative, days: s.days, budget: s.budget, lineWidth: 2)
                    .frame(maxHeight: .infinity)
                HStack {
                    Text(s.rangeLabel)
                    Spacer()
                    if s.lastPeriodSameDay > 0 {
                        let d = s.spent - s.lastPeriodSameDay
                        Text("前月比 \(d >= 0 ? "+" : "−")\(Fmt.short(abs(d)))")
                            .foregroundStyle(d > 0 ? Theme.accent : Theme.income)
                    }
                }
                .font(.system(size: 10, weight: .bold).width(.condensed))
                .foregroundStyle(Theme.faint)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "yensign.circle.fill")
                Text("\(monthTitle)の支出")
            }
            .font(.system(size: 12, weight: .bold))
            .widgetAccentable()
            Text(Fmt.yen(s.spent))
                .font(Theme.number(20, weight: .heavy))
            if s.budget > 0 {
                Gauge(value: Double(min(s.spent, s.budget)), in: 0...Double(max(1, s.budget))) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(over ? Theme.accent : Theme.ink)
                Text(over ? "\(Fmt.yen(-s.remaining)) オーバー" : "残り \(Fmt.yen(s.remaining)) · 1日 \(Fmt.short(s.dailyAllowance(at: now)))")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var circular: some View {
        Gauge(value: Double(min(s.spent, max(1, s.budget))), in: 0...Double(max(1, s.budget))) {
            Image(systemName: "yensign")
        } currentValueLabel: {
            Text(Fmt.short(s.budget > 0 ? s.remaining : s.spent))
                .font(Theme.number(14, weight: .heavy))
                .minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
    }
}

// MARK: - 最近の支出

struct RecentWidgetView: View {
    let summary: WidgetSummary
    let now: Date
    let family: WidgetFamily

    var body: some View {
        let items = Array(summary.recent.prefix(family == .systemLarge ? 6 : 3))
        VStack(alignment: .leading, spacing: family == .systemLarge ? 10 : 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("最近の記録")
                    .font(.system(size: 12, weight: .heavy).width(.condensed))
                    .foregroundStyle(Theme.accent)
                Text("今日 \(Fmt.yen(summary.today))")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
                Link(destination: URL(string: "moneyplan://add")!) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: 26, height: 26)
                        .background(Theme.accent, in: Circle())
                }
            }
            if items.isEmpty {
                Spacer()
                Text("Apple Pay で払うと\nここに表示されます")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                Spacer()
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 9) {
                        CategoryBadge(symbol: item.symbol, color: item.color, size: family == .systemLarge ? 30 : 26)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.merchant)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            Text(Fmt.when(item.date, now: now))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 4)
                        Text(item.income ? "+\(Fmt.yen(item.amount))" : Fmt.yen(item.amount))
                            .font(Theme.number(16, weight: .bold))
                            .foregroundStyle(item.income ? Theme.income : Theme.ink)
                            .monospacedDigit()
                    }
                }
                if family == .systemLarge {
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(summary.periodTitle.components(separatedBy: "年").last ?? "")
                            Text(Fmt.yen(summary.spent))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            if summary.budget > 0 {
                                Text("残り \(Fmt.yen(summary.remaining))")
                                    .foregroundStyle(summary.remaining < 0 ? Theme.accent : Theme.income)
                            }
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        StackBar(parts: summary.slices.map { ($0.color, $0.amount) } + (summary.otherAmount > 0 ? [(Theme.faint, summary.otherAmount)] : []), height: 8)
                    }
                }
            }
            if family != .systemLarge { Spacer(minLength: 0) }
        }
    }
}

// MARK: - 費目の内訳

struct CategoryWidgetView: View {
    let summary: WidgetSummary
    let now: Date
    let family: WidgetFamily

    var body: some View {
        let slices = summary.slices
        let parts = slices.map { ($0.color, $0.amount) } + (summary.otherAmount > 0 ? [(Theme.faint, summary.otherAmount)] : [])
        let total = max(1, summary.spent)
        switch family {
        case .systemSmall:
            VStack(spacing: 6) {
                ZStack {
                    Donut(parts: parts, lineWidth: 12)
                    VStack(spacing: 0) {
                        Text(slices.first?.name ?? "支出")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                        Text(Fmt.short(slices.first?.amount ?? 0))
                            .font(Theme.number(17, weight: .black))
                            .foregroundStyle(Theme.ink)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 18)
                }
                Text("\(summary.periodTitle.components(separatedBy: "年").last ?? "") \(Fmt.yen(summary.spent))")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
        default:
            let rows = family == .systemLarge ? slices : Array(slices.prefix(4))
            VStack(alignment: .leading, spacing: 10) {
                if family == .systemLarge {
                    HStack(alignment: .firstTextBaseline) {
                        Text("費目の内訳")
                            .font(.system(size: 12, weight: .heavy).width(.condensed))
                            .foregroundStyle(Theme.accent)
                        Spacer()
                        Text(summary.rangeLabel)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.muted)
                    }
                }
                HStack(spacing: 16) {
                    ZStack {
                        Donut(parts: parts, lineWidth: family == .systemLarge ? 18 : 13)
                        VStack(spacing: 0) {
                            Text("合計")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.muted)
                            Text(Fmt.short(summary.spent))
                                .font(Theme.number(family == .systemLarge ? 24 : 18, weight: .black))
                                .foregroundStyle(Theme.ink)
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 20)
                    }
                    .frame(width: family == .systemLarge ? 130 : 110, height: family == .systemLarge ? 130 : 110)
                    if family != .systemLarge {
                        legend(rows, total: total)
                    }
                }
                .frame(maxWidth: .infinity)
                if family == .systemLarge {
                    legend(rows, total: total)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func legend(_ rows: [WidgetSummary.Slice], total: Int) -> some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 8 : 5) {
            if rows.isEmpty {
                Text("まだ支出がありません")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
            ForEach(rows, id: \.self) { r in
                HStack(spacing: 6) {
                    if family == .systemLarge {
                        CategoryBadge(symbol: r.symbol, color: r.color, size: 24)
                    } else {
                        Circle().fill(r.color).frame(width: 7, height: 7)
                    }
                    Text(r.name)
                        .font(.system(size: family == .systemLarge ? 13 : 11, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if family == .systemLarge {
                        Text("\(Int((Double(r.amount) / Double(total) * 100).rounded()))%")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                    Text(Fmt.yen(r.amount))
                        .font(Theme.number(family == .systemLarge ? 15 : 13, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                }
            }
        }
    }
}

// MARK: - データがないとき

struct WidgetMessageView: View {
    let text: String
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(text)
        case .accessoryCircular:
            Image(systemName: "yensign.circle")
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("MoneyPlan").font(.system(size: 12, weight: .bold)).widgetAccentable()
                Text(text).font(.system(size: 11)).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "yensign.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.accent)
                Spacer(minLength: 0)
                Text(text)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
