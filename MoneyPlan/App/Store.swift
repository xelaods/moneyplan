import Foundation
import SwiftUI
import WidgetKit
import EventKit

/// 家計簿のデータを持つ。ショートカットからの記録（App Intents）も同じものを使う
@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published private(set) var file: LedgerFile
    @Published var now = Date()
    /// 直前に消した取引（元に戻す用）
    @Published private(set) var lastDeleted: [Txn] = []
    @Published private(set) var calendarStatus = EKEventStore.authorizationStatus(for: .event)

    static var isDemo: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }
    var isDemo: Bool { Self.isDemo }

    private init() {
        if Self.isDemo {
            file = Sample.ledger()
        } else {
            SharedStore.migrateIfNeeded()
            file = SharedStore.loadLedger()
        }
    }

    var ledger: Ledger { Ledger(file: file, now: now) }
    var categories: [TxnCategory] { file.categories }
    var expenseCategories: [TxnCategory] { file.categories.filter { $0.kind == .expense } }
    var incomeCategories: [TxnCategory] { file.categories.filter { $0.kind == .income } }
    var budget: Budget { file.budget }

    func category(_ id: String) -> TxnCategory { ledger.category(id) }

    /// これまでに使った支払い方法（新しい順）
    var accounts: [String] {
        var seen = Set<String>()
        return file.txns.sorted { $0.date > $1.date }.compactMap { t in
            guard !t.account.isEmpty, !seen.contains(t.account) else { return nil }
            seen.insert(t.account)
            return t.account
        }
    }

    /// 最後に Apple Pay から記録された日時
    var lastApplePay: Date? {
        file.txns.filter { $0.source == .applePay }.map(\.date).max()
    }

    func reload() {
        now = Date()
        calendarStatus = EKEventStore.authorizationStatus(for: .event)
        guard !isDemo else { return }
        let fresh = SharedStore.loadLedger()
        if fresh.txns != file.txns || fresh.budget != file.budget { file = fresh }
        publishSummary()
    }

    // MARK: 取引

    func suggestCategory(for merchant: String, kind: TxnKind) -> String {
        Categorizer.category(for: merchant, kind: kind, learned: file.learned)
    }

    @discardableResult
    func add(_ txn: Txn) -> Txn {
        var t = txn
        t.merchant = t.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        file.txns.append(t)
        commit()
        return t
    }

    func update(_ txn: Txn) {
        guard let i = file.txns.firstIndex(where: { $0.id == txn.id }) else { add(txn); return }
        file.txns[i] = txn
        commit()
    }

    func delete(_ ids: Set<UUID>) {
        lastDeleted = file.txns.filter { ids.contains($0.id) }
        file.txns.removeAll { ids.contains($0.id) }
        commit()
    }

    func undoDelete() {
        guard !lastDeleted.isEmpty else { return }
        file.txns.append(contentsOf: lastDeleted)
        lastDeleted = []
        commit()
    }

    func clearUndo() { lastDeleted = [] }

    /// 店名と費目の組み合わせを覚える（次から自動でその費目になる）
    func learn(merchant: String, categoryID: String, kind: TxnKind) {
        let key = Categorizer.key(merchant)
        guard !key.isEmpty else { return }
        let auto = Categorizer.category(for: merchant, kind: kind)
        if auto == categoryID {
            file.learned.removeValue(forKey: key)
        } else {
            file.learned[key] = categoryID
        }
        // 同じ店の、これまでの取引もまとめて直す
        for i in file.txns.indices where Categorizer.key(file.txns[i].merchant) == key && file.txns[i].kind == kind {
            file.txns[i].categoryID = categoryID
        }
        commit()
    }

    func forget(key: String) {
        file.learned.removeValue(forKey: key)
        commit()
    }

    /// 同じ日・同じ金額・同じ向きの取引がすでにあるか（Apple Pay で記録済みのものを CSV で二重に入れないため）
    func isDuplicate(date: Date, amount: Int, kind: TxnKind) -> Bool {
        let day = DayKey(date)
        return file.txns.contains { $0.amount == amount && $0.kind == kind && abs($0.day.days(to: day)) <= 1 }
    }

    /// 複数件をまとめて追加。重複を飛ばした件数も返す
    @discardableResult
    func importRows(_ rows: [(date: Date, amount: Int, kind: TxnKind, merchant: String)], source: TxnSource, account: String, skipDuplicates: Bool) -> (added: Int, skipped: Int) {
        var added = 0, skipped = 0
        for r in rows {
            if skipDuplicates && isDuplicate(date: r.date, amount: r.amount, kind: r.kind) { skipped += 1; continue }
            file.txns.append(Txn(date: r.date, amount: r.amount, kind: r.kind, merchant: r.merchant,
                                 categoryID: suggestCategory(for: r.merchant, kind: r.kind),
                                 account: account, source: source))
            added += 1
        }
        commit()
        return (added, skipped)
    }

    // MARK: 設定

    func setBudget(_ budget: Budget) {
        file.budget = budget
        commit()
    }

    func setCategoryBudget(_ id: String, _ value: Int) {
        if value > 0 { file.budget.byCategory[id] = value } else { file.budget.byCategory.removeValue(forKey: id) }
        commit()
    }

    func eraseAll() {
        file = LedgerFile()
        commit()
    }

    func restore(_ data: Data) -> Bool {
        guard let f = try? SharedStore.decoder.decode(LedgerFile.self, from: data) else { return false }
        file = f
        commit()
        return true
    }

    var backupData: Data? { try? SharedStore.encoder.encode(file) }

    // MARK: 保存とウィジェット

    private func commit() {
        now = Date()
        guard !isDemo else { return }
        file.txns.sort { $0.date > $1.date }
        SharedStore.saveLedger(file)
        publishSummary()
    }

    func publishSummary() {
        guard !isDemo else { return }
        SharedStore.saveSummary(Ledger(file: file, now: Date()).summary())
        WidgetCenter.shared.reloadAllTimelines()
    }

    func requestCalendarAccess() async {
        _ = try? await EKEventStore().requestFullAccessToEvents()
        calendarStatus = EKEventStore.authorizationStatus(for: .event)
        publishSummary()
    }

    var widgetBridge: WidgetBridge {
        if SharedStore.isShared { return .appGroup }
        if calendarStatus == .fullAccess && CalendarSummaryStore.enabled { return .calendar }
        return .none
    }

    enum WidgetBridge { case appGroup, calendar, none }
}
