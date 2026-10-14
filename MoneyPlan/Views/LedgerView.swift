import SwiftUI

/// 明細：期間ごとの取引を日付ごとに並べる。検索と費目の絞り込み、スワイプで削除
struct LedgerView: View {
    let edit: (EntryTarget) -> Void

    @EnvironmentObject var store: Store
    @State private var period: Period?
    @State private var direction: CGFloat = 1
    @State private var query = ""
    @State private var filter: Filter = .all

    enum Filter: Hashable {
        case all, expense, income, category(String)
    }

    var body: some View {
        let l = store.ledger
        let current = l.current
        let p = period ?? current
        let periodBinding = Binding<Period>(get: { period ?? current }, set: { period = $0 })
        let txns = filtered(l.txns(in: p))
        let groups = Dictionary(grouping: txns, by: \.day).sorted { $0.key > $1.key }

        NavigationStack {
            List {
                Section {
                    VStack(spacing: 14) {
                        PeriodSwitcher(period: periodBinding, direction: $direction, current: current)
                        HStack(spacing: 12) {
                            StatTile(title: "支出", value: Fmt.yen(l.spent(in: p)), tint: Theme.ink)
                            StatTile(title: "収入", value: Fmt.yen(l.income(in: p)), tint: Theme.income)
                            let net = l.income(in: p) - l.spent(in: p)
                            StatTile(title: "収支", value: Fmt.signedYen(net), tint: net >= 0 ? Theme.income : Theme.accent)
                        }
                        .id(p)
                        .transition(.cinematicSlide(direction))
                        FilterBar(filter: $filter, categories: store.categories)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                }

                if groups.isEmpty {
                    EmptyNote(symbol: query.isEmpty ? "tray" : "magnifyingglass",
                              title: query.isEmpty ? "この期間の記録はありません" : "見つかりませんでした",
                              message: query.isEmpty ? "Apple Pay の支払いや手入力した記録がここに並びます" : "店名・メモ・口座名で探せます")
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                ForEach(groups, id: \.key) { day, items in
                    Section {
                        ForEach(items) { t in
                            Button { edit(.edit(t)) } label: {
                                TxnRow(txn: t, category: l.category(t.categoryID), now: l.now)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Theme.card)
                            .listRowSeparatorTint(Theme.line)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    withAnimation(Motion.snappy) { store.delete([t.id]) }
                                } label: { Label("削除", systemImage: "trash") }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    var copy = t
                                    copy.id = UUID()
                                    copy.date = Date()
                                    store.add(copy)
                                } label: { Label("今日もう一度", systemImage: "arrow.uturn.forward") }
                                .tint(Theme.income)
                            }
                            .contextMenu {
                                Button { edit(.edit(t)) } label: { Label("編集", systemImage: "pencil") }
                                Button(role: .destructive) { store.delete([t.id]) } label: { Label("削除", systemImage: "trash") }
                            }
                        }
                    } header: {
                        DayHeader(day: day, items: items, now: l.now)
                    }
                }

                Color.clear.frame(height: 60)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("明細")
            .searchable(text: $query, prompt: "店名・メモ・口座で探す")
            .overlay(alignment: .bottomTrailing) { AddButton { edit(.new(.expense)) } }
            .animation(Motion.snappy, value: filter)
            .animation(Motion.cinematicFast, value: p)
        }
    }

    private func filtered(_ txns: [Txn]) -> [Txn] {
        txns.filter { t in
            switch filter {
            case .all: break
            case .expense: if t.kind != .expense { return false }
            case .income: if t.kind != .income { return false }
            case .category(let id): if t.categoryID != id { return false }
            }
            let q = query.trimmingCharacters(in: .whitespaces)
            guard !q.isEmpty else { return true }
            let k = Categorizer.key(q)
            return Categorizer.key(t.merchant).contains(k) || Categorizer.key(t.note).contains(k)
                || Categorizer.key(t.account).contains(k) || Categorizer.key(store.category(t.categoryID).name).contains(k)
                || Fmt.number(t.amount).contains(q) || String(t.amount).contains(q)
        }
    }
}

struct DayHeader: View {
    let day: DayKey
    let items: [Txn]
    let now: Date

    var body: some View {
        let spent = items.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount }
        let income = items.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount }
        HStack(alignment: .firstTextBaseline) {
            Text(Fmt.relativeDay(day.date, now: now))
                .font(.system(size: 14, weight: .heavy).width(.condensed))
                .foregroundStyle(Theme.weekdayColor(day.weekday))
            if Fmt.relativeDay(day.date, now: now) != Fmt.dayWithWeekday(day.date) {
                Text(Fmt.dayWithWeekday(day.date))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            if income > 0 {
                Text("+\(Fmt.yen(income))")
                    .font(Theme.number(14, weight: .bold))
                    .foregroundStyle(Theme.income)
            }
            if spent > 0 {
                Text(Fmt.yen(spent))
                    .font(Theme.number(14, weight: .bold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .textCase(nil)
    }
}

/// 絞り込みのチップ（横スクロール）
struct FilterBar: View {
    @Binding var filter: LedgerView.Filter
    let categories: [TxnCategory]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("すべて", .all)
                chip("支出", .expense)
                chip("収入", .income)
                ForEach(categories) { c in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        filter = filter == .category(c.id) ? .all : .category(c.id)
                    } label: {
                        CategoryChip(category: c, selected: filter == .category(c.id))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private func chip(_ title: String, _ f: LedgerView.Filter) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            filter = f
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(filter == f ? Theme.paper : Theme.ink)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(filter == f ? Theme.ink : Theme.fill, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
