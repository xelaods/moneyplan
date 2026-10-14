import XCTest
@testable import MoneyPlan

final class ParsingTests: XCTestCase {
    func testAmountParser() {
        XCTAssertEqual(AmountParser.parse("¥1,234"), 1234)
        XCTAssertEqual(AmountParser.parse("￥１，２３４"), 1234)
        XCTAssertEqual(AmountParser.parse("1,234円"), 1234)
        XCTAssertEqual(AmountParser.parse("JPY 980"), 980)
        XCTAssertEqual(AmountParser.parse("1234.00"), 1234)
        XCTAssertEqual(AmountParser.parse("-¥500"), 500)
        XCTAssertNil(AmountParser.parse("金額なし"))
    }

    func testCategorizer() {
        XCTAssertEqual(Categorizer.category(for: "セブン-イレブン 流山おおたかの森"), "food")
        XCTAssertEqual(Categorizer.category(for: "STARBUCKS COFFEE"), "cafe")
        XCTAssertEqual(Categorizer.category(for: "モバイルSuica"), "transport")
        XCTAssertEqual(Categorizer.category(for: "APPLE.COM/BILL"), "subscription")
        XCTAssertEqual(Categorizer.category(for: "よくわからない店"), TxnCategory.otherID)
        XCTAssertEqual(Categorizer.category(for: "給与 カ）ミライ", kind: .income), "salary")
        // 覚えた組み合わせが優先
        let key = Categorizer.key("セブン-イレブン 流山おおたかの森")
        XCTAssertEqual(Categorizer.category(for: "セブン-イレブン 流山おおたかの森", learned: [key: "daily"]), "daily")
    }

    func testNoticeParserIncome() {
        let now = DayKey(year: 2026, month: 10, day: 30).date
        let text = """
        【入金のお知らせ】
        2026/10/25 09:00
        振込入金 86,000円
        振込元：カ）ミライシヨウジ
        """
        let d = NoticeParser.parse(text, now: now)
        XCTAssertEqual(d?.amount, 86000)
        XCTAssertEqual(d?.kind, .income)
        XCTAssertEqual(d?.merchant, "カ）ミライシヨウジ")
        XCTAssertEqual(d.flatMap { $0.date }.map { DayKey($0) }, DayKey(year: 2026, month: 10, day: 25))
    }

    func testNoticeParserExpense() {
        let now = DayKey(year: 2026, month: 10, day: 14).date.addingTimeInterval(20 * 3600)
        let text = "カードご利用のお知らせ\nご利用日時：10/14 12:30\nご利用先：スターバックス\nご利用金額：680円"
        let d = NoticeParser.parse(text, now: now)
        XCTAssertEqual(d?.amount, 680)
        XCTAssertEqual(d?.kind, .expense)
        XCTAssertEqual(d?.merchant, "スターバックス")
    }

    func testCSV() {
        let csv = """
        "取引日","摘要","出金金額","入金金額","残高"
        "2026/10/01","カード　セブンイレブン","540","","100,000"
        "2026/10/25","給与","","86,000","186,000"
        """
        let rows = CSVImporter.parse(csv)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].amount, 540)
        XCTAssertEqual(rows[0].kind, .expense)
        XCTAssertEqual(rows[1].amount, 86000)
        XCTAssertEqual(rows[1].kind, .income)
    }
}

final class LedgerTests: XCTestCase {
    private func date(_ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        DayKey(year: 2026, month: m, day: d).date.addingTimeInterval(TimeInterval(h * 3600))
    }

    func testPeriodStartDay() {
        let p = Period(containing: date(10, 25), startDay: 25)
        XCTAssertEqual(p.month, MonthKey(year: 2026, month: 11))
        XCTAssertEqual(p.first, DayKey(year: 2026, month: 10, day: 25))
        XCTAssertEqual(p.last, DayKey(year: 2026, month: 11, day: 24))
        let q = Period(containing: date(10, 24), startDay: 25)
        XCTAssertEqual(q.month, MonthKey(year: 2026, month: 10))
        XCTAssertEqual(Period(containing: date(10, 14), startDay: 1).numberOfDays, 31)
    }

    func testTotalsAndAllowance() {
        var budget = Budget()
        budget.monthly = 31000
        let txns = [
            Txn(date: date(10, 1), amount: 1000, merchant: "A", categoryID: "food"),
            Txn(date: date(10, 10), amount: 2000, merchant: "B", categoryID: "cafe"),
            Txn(date: date(10, 11), amount: 500, merchant: "C", categoryID: "food"),
            Txn(date: date(10, 11), amount: 50000, kind: .income, merchant: "給与", categoryID: "salary"),
            Txn(date: date(9, 30), amount: 9999, merchant: "前月", categoryID: "food")
        ]
        let l = Ledger(txns: txns, categories: TxnCategory.defaults, budget: budget, now: date(10, 11, 20))
        XCTAssertEqual(l.spentThisPeriod, 3500)
        XCTAssertEqual(l.income(in: l.current), 50000)
        XCTAssertEqual(l.spentToday, 500)
        XCTAssertEqual(l.dayIndex, 11)
        XCTAssertEqual(l.daysLeft, 21)
        // 昨日までに 3,000 使って、残り 28,000 を 21日で割る
        XCTAssertEqual(l.dailyAllowance, 28000 / 21)
        XCTAssertEqual(l.byCategory(in: l.current).first?.category.id, "cafe")
        XCTAssertEqual(l.cumulative(in: l.current).count, 11)
        XCTAssertEqual(l.cumulative(in: l.current).last, 3500)
        XCTAssertEqual(l.lastPeriodSameDay, 0)
    }

    func testSummaryRollsOverToNewPeriod() {
        var budget = Budget()
        budget.monthly = 10000
        let l = Ledger(txns: [Txn(date: date(10, 31), amount: 800, merchant: "A", categoryID: "food")],
                       categories: TxnCategory.defaults, budget: budget, now: date(10, 31, 20))
        let s = l.summary()
        XCTAssertEqual(s.spent, 800)
        let next = s.adjusted(for: date(11, 1, 9))
        XCTAssertEqual(next.spent, 0)
        XCTAssertEqual(next.periodTitle, "2026年11月")
        let sameDayLater = s.adjusted(for: date(10, 31, 23))
        XCTAssertEqual(sameDayLater.today, 800)
    }

    func testSummaryRoundTrip() throws {
        let s = Sample.summary()
        let data = try SharedStore.encoder.encode(s)
        let back = try SharedStore.decoder.decode(WidgetSummary.self, from: data)
        XCTAssertEqual(back.spent, s.spent)
        XCTAssertEqual(back.recent.count, s.recent.count)
    }
}
