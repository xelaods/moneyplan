import Foundation

/// 見本のデータ（スクリーンショット・ウィジェットのプレビュー用）
enum Sample {
    private static let shops: [(String, String, ClosedRange<Int>, String)] = [
        ("セブン-イレブン 流山おおたかの森", "food", 180...780, "Apple Pay"),
        ("ファミリーマート 舞浜駅前", "food", 150...620, "Apple Pay"),
        ("スターバックス 流山おおたかの森", "cafe", 480...780, "Apple Pay"),
        ("モバイルSuica", "transport", 1000...3000, "Suica"),
        ("すき家", "food", 450...890, "Apple Pay"),
        ("マツモトキヨシ", "daily", 300...2400, "Apple Pay"),
        ("ダイソー", "daily", 110...880, "Apple Pay"),
        ("紀伊國屋書店", "study", 900...2600, "Apple Pay"),
        ("ラウンドワン", "hobby", 900...3200, "Apple Pay"),
        ("UNIQLO", "fashion", 1990...5990, "Apple Pay"),
        ("大学生協", "food", 380...720, "Apple Pay")
    ]

    static func ledger(now: Date = Date()) -> LedgerFile {
        var file = LedgerFile()
        file.budget.monthly = 60000
        var seed: UInt64 = 20261014
        func rand(_ r: ClosedRange<Int>) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return r.lowerBound + Int((seed >> 33) % UInt64(r.upperBound - r.lowerBound + 1))
        }
        let today = DayKey(now)
        var txns: [Txn] = []
        for back in 0..<75 {
            let day = today.adding(days: -back)
            let count = rand(0...3)
            for i in 0..<count {
                let shop = shops[rand(0...(shops.count - 1))]
                var amount = rand(shop.2)
                amount = amount / 10 * 10
                let hour = [8, 12, 13, 16, 18, 19, 21][rand(0...6)]
                let date = day.date.addingTimeInterval(TimeInterval(hour * 3600 + rand(0...59) * 60 + i))
                if back == 0 && date > now { continue }
                txns.append(Txn(date: date, amount: amount, merchant: shop.0, categoryID: shop.1, account: shop.3, source: .applePay))
            }
            if day.day == 25 {
                txns.append(Txn(date: day.date.addingTimeInterval(9 * 3600), amount: 86000, kind: .income, merchant: "給与 カ）ミライシヨウジ", categoryID: "salary", account: "住信SBIネット銀行", source: .bank))
            }
            if day.day == 3 {
                txns.append(Txn(date: day.date.addingTimeInterval(7 * 3600), amount: 3000, merchant: "Claude Pro", categoryID: "subscription", account: "VISA", source: .csv))
                txns.append(Txn(date: day.date.addingTimeInterval(7 * 3600 + 60), amount: 2970, merchant: "ahamo", categoryID: "subscription", account: "VISA", source: .csv))
            }
            if day.day == 10 {
                txns.append(Txn(date: day.date.addingTimeInterval(10 * 3600), amount: 3278, merchant: "chocoZAP", categoryID: "health", account: "VISA", source: .bank))
            }
        }
        file.txns = txns.sorted { $0.date > $1.date }
        return file
    }

    static func summary(now: Date = Date()) -> WidgetSummary {
        Ledger(file: ledger(now: now), now: now).summary()
    }
}
