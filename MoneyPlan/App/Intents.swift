import AppIntents
import Foundation

enum RecordError: Error, CustomLocalizedStringResourceConvertible {
    case noAmount(String)
    case noNotice

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noAmount(let s): return "金額を読み取れませんでした（\(s)）"
        case .noNotice: return "文章から金額を見つけられませんでした"
        }
    }
}

/// ショートカットの「取引」オートメーションから呼ぶ。アプリは開かずに裏で保存する
struct RecordPaymentIntent: AppIntent {
    static var title: LocalizedStringResource = "支払いを記録"
    static var description = IntentDescription("Apple Pay の支払いなどを MoneyPlan に記録します。ショートカットの「取引」オートメーションの金額・店舗・カードをそのまま渡してください。費目は店名から自動で決まります。")
    static var openAppWhenRun = false

    @Parameter(title: "金額", description: "「¥1,234」「1234」など。記号やカンマがあっても読み取ります")
    var amount: String

    @Parameter(title: "店名")
    var merchant: String?

    @Parameter(title: "カード")
    var card: String?

    @Parameter(title: "収入として記録", default: false)
    var isIncome: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$amount)を\(\.$merchant)で記録") {
            \.$card
            \.$isIncome
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let yen = AmountParser.parse(amount), yen > 0 else { throw RecordError.noAmount(amount) }
        let store = Store.shared
        let kind: TxnKind = isIncome ? .income : .expense
        let name = (merchant ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let t = store.add(Txn(date: Date(), amount: yen, kind: kind, merchant: name,
                              categoryID: store.suggestCategory(for: name, kind: kind),
                              account: (card ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                              source: .applePay))
        let c = store.category(t.categoryID)
        let l = store.ledger
        let line: String
        if kind == .expense && l.budget.monthly > 0 {
            line = "\(Fmt.yen(yen))（\(c.name)）を記録しました。今月の残り \(Fmt.yen(l.remaining))"
        } else {
            line = "\(Fmt.yen(yen))（\(c.name)）を記録しました"
        }
        return .result(value: line, dialog: IntentDialog(stringLiteral: line))
    }
}

/// 銀行やカードの通知メール・SMS の文章から記録する（共有シートやショートカットから）
struct RecordNoticeIntent: AppIntent {
    static var title: LocalizedStringResource = "通知文から記録"
    static var description = IntentDescription("入出金通知などの文章から、日付・金額・入金か出金か・相手を読み取って記録します。")
    static var openAppWhenRun = false

    @Parameter(title: "文章")
    var text: String

    @Parameter(title: "口座・カード名")
    var account: String?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let d = NoticeParser.parse(text) else { throw RecordError.noNotice }
        let store = Store.shared
        let t = store.add(Txn(date: d.date ?? Date(), amount: d.amount, kind: d.kind, merchant: d.merchant,
                              categoryID: store.suggestCategory(for: d.merchant, kind: d.kind),
                              account: (account ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                              source: .bank))
        let line = "\(t.kind.label) \(Fmt.yen(t.amount))（\(t.merchant)）を記録しました"
        return .result(value: line, dialog: IntentDialog(stringLiteral: line))
    }
}

/// 今月の支出を読み上げる・ほかのショートカットで使う
struct MonthSpentIntent: AppIntent {
    static var title: LocalizedStringResource = "今月の支出を取得"
    static var description = IntentDescription("今月使った金額と、予算の残りを返します。")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let store = Store.shared
        store.reload()
        let l = store.ledger
        var line = "\(l.current.shortTitle)は \(Fmt.yen(l.spentThisPeriod)) 使いました"
        if l.budget.monthly > 0 {
            line += l.remaining >= 0 ? "。残り \(Fmt.yen(l.remaining))、1日 \(Fmt.yen(l.dailyAllowance)) まで使えます"
                                     : "。予算を \(Fmt.yen(-l.remaining)) 超えています"
        }
        return .result(value: l.spentThisPeriod, dialog: IntentDialog(stringLiteral: line))
    }
}

struct OpenAddIntent: AppIntent {
    static var title: LocalizedStringResource = "支出を手入力"
    static var description = IntentDescription("MoneyPlan を開いて、入力画面を表示します。")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.pendingAdd = true
        return .result()
    }
}

struct MoneyPlanShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RecordPaymentIntent(),
                    phrases: ["\(.applicationName)に支払いを記録", "\(.applicationName)で記録"],
                    shortTitle: "支払いを記録",
                    systemImageName: "yensign.circle")
        AppShortcut(intent: MonthSpentIntent(),
                    phrases: ["\(.applicationName)で今月の支出", "\(.applicationName)の残り"],
                    shortTitle: "今月の支出",
                    systemImageName: "chart.bar")
        AppShortcut(intent: OpenAddIntent(),
                    phrases: ["\(.applicationName)に入力"],
                    shortTitle: "手入力",
                    systemImageName: "plus.circle")
    }
}

/// ショートカットやウィジェットから開いたときの行き先
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    @Published var pendingAdd = false
}
