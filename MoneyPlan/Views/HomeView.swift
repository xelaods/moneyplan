import SwiftUI

struct HomeView: View {
    let edit: (EntryTarget) -> Void
    let open: (MainTabView.Tab) -> Void

    @EnvironmentObject var store: Store
    @State private var showGuide = false

    var body: some View {
        let l = store.ledger
        let p = l.current
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ScreenHeader(title: p.title, subtitle: "\(p.rangeLabel) · あと\(l.daysLeft)日")
                        .padding(.top, 6)
                        .cinematicReveal(0)

                    SpendHero(ledger: l)
                        .cinematicReveal(1)

                    if l.txns.isEmpty {
                        SetupCard { showGuide = true }
                            .cinematicReveal(2)
                    }

                    PaceCard(ledger: l)
                        .cinematicReveal(2)
                        .cinematicScroll()

                    Button { open(.analysis) } label: { CategoryCard(ledger: l) }
                        .buttonStyle(PressableCardStyle())
                        .cinematicReveal(3)
                        .cinematicScroll()

                    RecentCard(ledger: l, edit: edit, more: { open(.ledger) })
                        .cinematicReveal(4)
                        .cinematicScroll()

                    Color.clear.frame(height: 70)
                }
                .padding(.horizontal, 16)
            }
            .background(Theme.paper.ignoresSafeArea())
            .overlay(alignment: .bottomTrailing) { AddButton { edit(.new(.expense)) } }
            .refreshable { store.reload() }
            .sheet(isPresented: $showGuide) {
                NavigationStack { ShortcutGuideView() }
                    .presentationCornerRadius(28)
            }
        }
    }
}

/// 今月使ったお金・予算の残り・1日あたり
struct SpendHero: View {
    let ledger: Ledger

    var body: some View {
        let l = ledger
        let hasBudget = l.budget.monthly > 0
        let over = l.remaining < 0
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: "今月使ったお金")
                Spacer()
                if hasBudget {
                    Text("予算 \(Fmt.yen(l.budget.monthly))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
            }
            Amount(value: l.spentThisPeriod, size: 50)
            if hasBudget {
                VStack(alignment: .leading, spacing: 6) {
                    BudgetBar(spent: l.spentThisPeriod, budget: l.budget.monthly, target: l.paceTarget, height: 12)
                    HStack {
                        Text(paceText(l))
                            .foregroundStyle(Theme.paceColor(spent: l.spentThisPeriod, target: l.paceTarget, budget: l.budget.monthly))
                        Spacer()
                        Text("目安 \(Fmt.yen(l.paceTarget))")
                            .foregroundStyle(Theme.muted)
                    }
                    .font(.system(size: 12, weight: .semibold))
                }
            }
            DashedRule()
            HStack(alignment: .top, spacing: 12) {
                if hasBudget {
                    StatTile(title: over ? "予算オーバー" : "残り",
                             value: Fmt.yen(abs(l.remaining)),
                             tint: over ? Theme.accent : Theme.ink)
                    StatTile(title: "今日から1日", value: Fmt.yen(l.dailyAllowance),
                             tint: Theme.income, caption: "今日 \(Fmt.yen(l.spentToday)) 使用")
                } else {
                    StatTile(title: "今日", value: Fmt.yen(l.spentToday))
                    StatTile(title: "収入", value: Fmt.yen(l.income(in: l.current)), tint: Theme.income)
                }
                StatTile(title: "前月の同じ日まで", value: Fmt.yen(l.lastPeriodSameDay),
                         caption: diffText(l.spentThisPeriod - l.lastPeriodSameDay))
            }
        }
        .card(padding: 18)
    }

    private func paceText(_ l: Ledger) -> String {
        if l.remaining < 0 { return "予算を超えています" }
        let d = l.spentThisPeriod - l.paceTarget
        if d <= 0 { return "目安より \(Fmt.yen(-d)) 少ない" }
        return "目安より \(Fmt.yen(d)) 多い"
    }

    private func diffText(_ d: Int) -> String {
        d == 0 ? "前月と同じ" : (d > 0 ? "\(Fmt.yen(d)) 多い" : "\(Fmt.yen(-d)) 少ない")
    }
}

/// 累計のグラフと見込み
struct PaceCard: View {
    let ledger: Ledger

    var body: some View {
        let l = ledger
        let p = l.current
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: "ペース")
                Spacer()
                Text("このままだと \(Fmt.yen(l.projected))")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(l.budget.monthly > 0 && l.projected > l.budget.monthly ? Theme.accent : Theme.ink)
            }
            PaceChart(cumulative: l.cumulative(in: p), days: p.numberOfDays, budget: l.budget.monthly)
                .frame(height: 120)
            HStack {
                Text("\(p.first.month)/\(p.first.day)")
                Spacer()
                Text("\(p.last.month)/\(p.last.day)")
            }
            .font(.system(size: 10, weight: .semibold).width(.condensed))
            .foregroundStyle(Theme.faint)
            WeekStrip(ledger: l)
        }
        .card(padding: 18)
    }
}

/// 直近7日の支出（日ごとの棒）
struct WeekStrip: View {
    let ledger: Ledger

    var body: some View {
        let today = DayKey(ledger.now)
        let days = (0..<7).map { today.adding(days: $0 - 6) }
        let values = days.map { ledger.spent(on: $0) }
        let top = max(1, values.max() ?? 1)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(zip(days, values)), id: \.0) { day, v in
                VStack(spacing: 4) {
                    Text(v > 0 ? Fmt.short(v) : "")
                        .font(.system(size: 9, weight: .bold).width(.condensed))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(day == today ? Theme.accent : Theme.ink.opacity(0.18))
                        .frame(height: max(3, 38 * CGFloat(v) / CGFloat(top)))
                    Text(Fmt.weekdaySymbol(day.weekday))
                        .font(.system(size: 11, weight: day == today ? .heavy : .semibold))
                        .foregroundStyle(day == today ? Theme.ink : Theme.weekdayColor(day.weekday).opacity(0.7))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 70)
    }
}

/// 費目の内訳（上位）
struct CategoryCard: View {
    let ledger: Ledger

    var body: some View {
        let items = ledger.byCategory(in: ledger.current)
        let total = max(1, items.reduce(0) { $0 + $1.amount })
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: "費目")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.faint)
            }
            if items.isEmpty {
                Text("まだ支出がありません")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
            } else {
                StackBar(parts: items.map { ($0.category.color, $0.amount) }, height: 12)
                VStack(spacing: 10) {
                    ForEach(items.prefix(4), id: \.category.id) { item in
                        HStack(spacing: 10) {
                            CategoryBadge(symbol: item.category.symbol, color: item.category.color, size: 28)
                            Text(item.category.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Text("\(Int((Double(item.amount) / Double(total) * 100).rounded()))%")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.muted)
                            Spacer()
                            Text(Fmt.yen(item.amount))
                                .font(Theme.number(17, weight: .bold))
                                .foregroundStyle(Theme.ink)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .card(padding: 18)
    }
}

/// 最近の取引
struct RecentCard: View {
    let ledger: Ledger
    let edit: (EntryTarget) -> Void
    let more: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: "最近の記録")
                Spacer()
                if !ledger.txns.isEmpty {
                    Button("すべて見る", action: more)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            if ledger.txns.isEmpty {
                EmptyNote(symbol: "wave.3.right", title: "まだ記録がありません",
                          message: "Apple Pay で支払うと、ここに自動で並びます。\n右下の＋から手入力もできます。")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(ledger.txns.prefix(6).enumerated()), id: \.element.id) { i, t in
                        if i > 0 { Divider().overlay(Theme.line).padding(.leading, 50) }
                        Button { edit(.edit(t)) } label: {
                            TxnRow(txn: t, category: ledger.category(t.categoryID), now: ledger.now, showsDate: true)
                                .padding(.vertical, 9)
                        }
                        .buttonStyle(PressableCardStyle())
                    }
                }
            }
        }
        .card(padding: 18)
    }
}

/// はじめに：ショートカットの設定へ
struct SetupCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "wave.3.right.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Apple Pay を自動で記録する")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text("ショートカットのオートメーションを1つ作るだけ。2分で終わります")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.faint)
            }
            .card(padding: 18)
        }
        .buttonStyle(PressableCardStyle())
    }
}
