import SwiftUI
import UIKit

/// 銀行・カードの通知文（メール・SMS）を貼り付けて記録
struct NoticeImportView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var account = ""
    @State private var saved: String?

    var body: some View {
        let draft = NoticeParser.parse(text)
        Form {
            Section {
                TextEditor(text: $text)
                    .frame(minHeight: 150)
                    .font(.system(size: 14))
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("例）\n【入金のお知らせ】\n2026/10/25 09:00\n振込入金 86,000円\n振込元：カ）ミライシヨウジ")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.faint)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                    }
                Button {
                    if let s = UIPasteboard.general.string { text = s }
                } label: {
                    Label("クリップボードから貼り付け", systemImage: "doc.on.clipboard")
                }
            } header: {
                Text("通知の文章")
            } footer: {
                Text("銀行やカード会社から届く入出金・利用通知のメールや SMS を、そのまま貼り付けてください。")
            }

            if let d = draft {
                Section("読み取った内容") {
                    LabeledContent("種類", value: d.kind.label)
                    LabeledContent("金額") {
                        Text(Fmt.yen(d.amount))
                            .font(Theme.number(20, weight: .bold))
                            .foregroundStyle(d.kind == .income ? Theme.income : Theme.ink)
                    }
                    LabeledContent("日時", value: d.date.map { "\(Fmt.full($0)) \(Fmt.time($0))" } ?? "今（文章に日付なし）")
                    LabeledContent("相手・内容", value: d.merchant)
                    LabeledContent("費目", value: store.category(store.suggestCategory(for: d.merchant, kind: d.kind)).name)
                    TextField("口座・カード名（任意）", text: $account)
                }
                Section {
                    Button {
                        store.add(Txn(date: d.date ?? Date(), amount: d.amount, kind: d.kind, merchant: d.merchant,
                                      categoryID: store.suggestCategory(for: d.merchant, kind: d.kind),
                                      account: account, source: .bank))
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        saved = "\(d.kind.label) \(Fmt.yen(d.amount)) を記録しました"
                        text = ""
                    } label: {
                        Label("この内容で記録", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                    }
                    if store.isDuplicate(date: d.date ?? Date(), amount: d.amount, kind: d.kind) {
                        Label("同じ日・同じ金額の記録がすでにあります", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.warning)
                    }
                }
            } else if !text.isEmpty {
                Section {
                    Label("金額を見つけられませんでした", systemImage: "questionmark.circle")
                        .foregroundStyle(Theme.muted)
                }
            }

            Section {
                Text("ショートカットの「通知文から記録」アクションを使うと、共有シートから送るだけで記録できます。")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("通知文から記録")
        .navigationBarTitleDisplayMode(.inline)
        .alert(saved ?? "", isPresented: Binding(get: { saved != nil }, set: { if !$0 { saved = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }
}

/// CSV の読み込み前の確認
struct CSVPreviewView: View {
    let rows: [CSVImporter.Row]
    let done: (String) -> Void

    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var account = ""
    @State private var skipDuplicates = true

    var body: some View {
        let expense = rows.filter { $0.kind == .expense }
        let income = rows.filter { $0.kind == .income }
        let dupes = rows.filter { store.isDuplicate(date: $0.date, amount: $0.amount, kind: $0.kind) }.count
        Form {
            Section {
                LabeledContent("件数", value: "\(rows.count)件")
                LabeledContent("期間", value: range)
                LabeledContent("支出", value: "\(expense.count)件 \(Fmt.yen(expense.reduce(0) { $0 + $1.amount }))")
                LabeledContent("収入", value: "\(income.count)件 \(Fmt.yen(income.reduce(0) { $0 + $1.amount }))")
                TextField("口座・カード名（例：住信SBI）", text: $account)
                Toggle("重複しそうなものは飛ばす（\(dupes)件）", isOn: $skipDuplicates)
            } footer: {
                Text("Apple Pay で記録済みの支払いと同じ日・同じ金額のものを飛ばします。")
            }
            Section("中身") {
                ForEach(Array(rows.prefix(50).enumerated()), id: \.offset) { _, r in
                    HStack {
                        Text(Fmt.monthDay(r.date))
                            .font(Theme.number(14, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 44, alignment: .leading)
                        Text(r.merchant.isEmpty ? "—" : r.merchant)
                            .font(.system(size: 14))
                            .lineLimit(1)
                        Spacer()
                        Text(r.kind == .income ? "+\(Fmt.yen(r.amount))" : Fmt.yen(r.amount))
                            .font(Theme.number(15, weight: .bold))
                            .foregroundStyle(r.kind == .income ? Theme.income : Theme.ink)
                    }
                }
                if rows.count > 50 {
                    Text("ほか \(rows.count - 50)件").foregroundStyle(Theme.muted)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("CSV の読み込み")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("やめる") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("読み込む") {
                    let r = store.importRows(rows.map { (date: $0.date, amount: $0.amount, kind: $0.kind, merchant: $0.merchant) }, source: .csv,
                                             account: account.trimmingCharacters(in: .whitespaces), skipDuplicates: skipDuplicates)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                    done(r.skipped > 0 ? "\(r.added)件を読み込みました（\(r.skipped)件は重複のため飛ばしました）" : "\(r.added)件を読み込みました")
                }
                .bold()
            }
        }
    }

    private var range: String {
        guard let a = rows.map(\.date).min(), let b = rows.map(\.date).max() else { return "—" }
        return "\(Fmt.full(a))〜\(Fmt.full(b))"
    }
}

/// Apple Pay を自動で記録するショートカットの作り方
struct ShortcutGuideView: View {
    @EnvironmentObject var store: Store
    @State private var testDone = false

    private let steps: [(String, String, String)] = [
        ("bolt.fill", "オートメーションを作る", "ショートカットアプリの「オートメーション」タブで右上の＋をタップし、「取引」を選びます。"),
        ("creditcard.fill", "カードを選ぶ", "記録したいカード（Wallet に入っているもの）にチェックを入れ、「すぐに実行」を選んで「次へ」。"),
        ("square.stack.3d.up.fill", "アクションを追加", "「新規の空のオートメーション」→「アクションを追加」で「MoneyPlan」を探し、「支払いを記録」を選びます。"),
        ("arrow.triangle.branch", "値をつなぐ", "「金額」に「ショートカットの入力 › 金額」、店名に「加盟店」、カードに「カードまたはパス」を入れます（青い文字をタップして変数を選ぶ）。"),
        ("checkmark.seal.fill", "完了", "右上の完了を押せば設定は終わりです。次から Apple Pay で払うたびに、アプリを開かずに記録されます。")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Apple Pay を自動で記録")
                        .font(.system(size: 28, weight: .heavy).width(.condensed))
                        .foregroundStyle(Theme.ink)
                    Text("iPhone のショートカットが、タッチ決済のたびに金額・お店・カードを MoneyPlan に渡します。費目はお店の名前から自動で決まります。")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                }
                .cinematicReveal(0)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                        HStack(alignment: .top, spacing: 14) {
                            VStack(spacing: 0) {
                                ZStack {
                                    Circle().fill(i == steps.count - 1 ? Theme.income : Theme.ink)
                                    Text("\(i + 1)")
                                        .font(Theme.number(15, weight: .black))
                                        .foregroundStyle(Theme.paper)
                                }
                                .frame(width: 28, height: 28)
                                if i < steps.count - 1 {
                                    Rectangle().fill(Theme.line).frame(width: 2).frame(maxHeight: .infinity)
                                }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Label(s.1, systemImage: s.0)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(Theme.ink)
                                Text(s.2)
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.bottom, 20)
                        }
                        .cinematicReveal(i + 1)
                    }
                }
                .card(padding: 18)

                Button {
                    if let url = URL(string: "shortcuts://") { UIApplication.shared.open(url) }
                } label: {
                    Label("ショートカットを開く", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(GlassPrimaryButtonStyle())

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "うまく記録されないとき")
                    tip("「すぐに実行」になっていないと、毎回通知をタップするまで記録されません。")
                    tip("カードによっては金額や店名が空で届くことがあります。その場合は明細から直してください。")
                    tip("交通系IC（Suica・PASMO）の改札やネットでの支払いは「取引」の対象外です。銀行の通知文や CSV で補えます。")
                }
                .card(padding: 18)

                Button {
                    store.add(Txn(date: Date(), amount: 1, merchant: "テスト（消してOK）", categoryID: TxnCategory.otherID,
                                  account: "テスト", source: .applePay))
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    testDone = true
                } label: {
                    Label(testDone ? "明細に ¥1 のテストを追加しました" : "ウィジェットの表示をテスト（¥1 を記録）", systemImage: testDone ? "checkmark" : "testtube.2")
                }
                .buttonStyle(GlassSecondaryButtonStyle())
                .disabled(testDone)
            }
            .padding(16)
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tip(_ s: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(Theme.accent).frame(width: 5, height: 5).padding(.top, 7)
            Text(s).font(.system(size: 13)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        }
    }
}
