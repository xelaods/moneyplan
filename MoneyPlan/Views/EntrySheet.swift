import SwiftUI
import UIKit

/// 記録の入力・編集。上に大きな金額、下にテンキー
struct EntrySheet: View {
    let target: EntryTarget

    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var txn: Txn
    @State private var digits: String
    @State private var categoryPicked: Bool
    @State private var confirmDelete = false
    @FocusState private var focused: Field?

    enum Field { case merchant, account, note }

    init(target: EntryTarget) {
        self.target = target
        switch target {
        case .new(let kind):
            _txn = State(initialValue: Txn(date: Date(), amount: 0, kind: kind, merchant: "",
                                           categoryID: kind == .expense ? TxnCategory.otherID : TxnCategory.otherIncomeID))
            _digits = State(initialValue: "")
            _categoryPicked = State(initialValue: false)
        case .edit(let t):
            _txn = State(initialValue: t)
            _digits = State(initialValue: String(t.amount))
            _categoryPicked = State(initialValue: true)
        }
    }

    private var isNew: Bool { if case .new = target { return true } else { return false } }
    private var amount: Int { Int(digits) ?? 0 }
    private var category: TxnCategory { store.category(txn.categoryID) }
    private var categories: [TxnCategory] { txn.kind == .expense ? store.expenseCategories : store.incomeCategories }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 18) {
                    amountDisplay
                    categoryGrid
                    detailFields
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            if focused == nil {
                Keypad(digits: $digits)
                    .padding(.horizontal, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            saveBar
        }
        .background(Theme.paper.ignoresSafeArea())
        .animation(Motion.snappy, value: focused)
        .confirmationDialog("この記録を削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                store.delete([txn.id])
                dismiss()
            }
        }
    }

    // MARK: 上の部分

    private var header: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(GlassCircleButtonStyle(size: 38))
            Spacer()
            Picker("", selection: Binding(get: { txn.kind }, set: { setKind($0) })) {
                ForEach(TxnKind.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            Spacer()
            if isNew {
                Color.clear.frame(width: 38, height: 38)
            } else {
                Button { confirmDelete = true } label: { Image(systemName: "trash") }
                    .buttonStyle(GlassCircleButtonStyle(size: 38))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var amountDisplay: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                CategoryBadge(symbol: category.symbol, color: category.color, size: 26)
                Text(category.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(category.color)
                if txn.source != .manual {
                    Text("· \(txn.source.label)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
            }
            .animation(Motion.snappy, value: txn.categoryID)
            Amount(value: amount, size: 58, color: amount == 0 ? Theme.faint : (txn.kind == .income ? Theme.income : Theme.ink),
                   sign: txn.kind == .income ? "+" : "")
                .animation(Motion.snappy, value: amount)
                .onTapGesture { focused = nil }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
    }

    private var categoryGrid: some View {
        FlowLayout(spacing: 8) {
            ForEach(categories) { c in
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    txn.categoryID = c.id
                    categoryPicked = true
                } label: {
                    CategoryChip(category: c, selected: c.id == txn.categoryID)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var detailFields: some View {
        VStack(spacing: 0) {
            fieldRow(symbol: "storefront", title: "店名・内容") {
                TextField(txn.kind == .expense ? "例：セブン-イレブン" : "例：給与", text: $txn.merchant)
                    .focused($focused, equals: .merchant)
                    .submitLabel(.next)
                    .onSubmit { focused = .account }
                    .onChange(of: txn.merchant) { _, name in
                        // 費目を自分で選んでいなければ、店名から自動で決める
                        if !categoryPicked {
                            withAnimation(Motion.snappy) { txn.categoryID = store.suggestCategory(for: name, kind: txn.kind) }
                        }
                    }
            }
            Divider().overlay(Theme.line)
            fieldRow(symbol: "creditcard", title: "支払い方法") {
                TextField("例：Apple Pay・VISA", text: $txn.account)
                    .focused($focused, equals: .account)
                    .submitLabel(.next)
                    .onSubmit { focused = .note }
            }
            if focused == .account && !store.accounts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(store.accounts.prefix(8), id: \.self) { a in
                            Button(a) { txn.account = a; focused = .note }
                                .buttonStyle(GlassCapsuleButtonStyle())
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            Divider().overlay(Theme.line)
            fieldRow(symbol: "calendar", title: "日時") {
                DatePicker("", selection: $txn.date, in: ...Date().addingTimeInterval(86400 * 31))
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "ja_JP"))
                    .environment(\.timeZone, JST.timeZone)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            Divider().overlay(Theme.line)
            fieldRow(symbol: "text.alignleft", title: "メモ") {
                TextField("任意", text: $txn.note)
                    .focused($focused, equals: .note)
                    .submitLabel(.done)
                    .onSubmit { focused = nil }
            }
        }
        .padding(.horizontal, 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line, lineWidth: 0.75))
    }

    private func fieldRow<Content: View>(symbol: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .fixedSize()
            content()
                .font(.system(size: 15))
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 50)
    }

    private var saveBar: some View {
        Button(action: save) {
            Label(isNew ? "記録する" : "保存", systemImage: "checkmark")
        }
        .buttonStyle(GlassPrimaryButtonStyle(tint: txn.kind == .income ? Theme.income : Theme.ink))
        .disabled(amount <= 0)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    // MARK: 操作

    private func setKind(_ kind: TxnKind) {
        guard kind != txn.kind else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(Motion.snappy) {
            txn.kind = kind
            txn.categoryID = store.suggestCategory(for: txn.merchant, kind: kind)
            categoryPicked = false
        }
    }

    private func save() {
        guard amount > 0 else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        var t = txn
        t.amount = amount
        t.merchant = t.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        t.account = t.account.trimmingCharacters(in: .whitespacesAndNewlines)
        if isNew {
            store.add(t)
        } else {
            store.update(t)
        }
        // 自分で費目を選んだら、その店の費目として覚える
        let auto = store.suggestCategory(for: t.merchant, kind: t.kind)
        if categoryPicked && !t.merchant.isEmpty && auto != t.categoryID {
            store.learn(merchant: t.merchant, categoryID: t.categoryID, kind: t.kind)
        }
        dismiss()
    }
}

/// レシート風のテンキー
struct Keypad: View {
    @Binding var digits: String

    private let keys: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["00", "0", "⌫"]]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in
                        Button { tap(key) } label: {
                            Group {
                                if key == "⌫" {
                                    Image(systemName: "delete.left").font(.system(size: 20, weight: .semibold))
                                } else {
                                    Text(key).font(Theme.number(28, weight: .bold))
                                }
                            }
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line, lineWidth: 0.75))
                        }
                        .buttonStyle(KeyStyle())
                        .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                            if key == "⌫" { digits = ""; UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
                        })
                    }
                }
            }
        }
    }

    private func tap(_ key: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(Motion.snappy) {
            switch key {
            case "⌫":
                if !digits.isEmpty { digits.removeLast() }
            default:
                guard digits.count + key.count <= 8 else { return }
                if digits.isEmpty && key.hasPrefix("0") { return }
                digits += key
            }
        }
    }

    struct KeyStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .brightness(configuration.isPressed ? -0.04 : 0)
                .animation(.snappy(duration: 0.12), value: configuration.isPressed)
        }
    }
}

/// 中身の幅のまま、入りきらなければ次の行に折り返して並べる
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            // 行ごとに中央揃え
            var x = bounds.minX + (bounds.width - row.width) / 2
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let next = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if next > width && !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(i)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
