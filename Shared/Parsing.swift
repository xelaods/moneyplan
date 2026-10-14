import Foundation

// MARK: - 金額

enum AmountParser {
    /// 「¥1,234」「1,234円」「JPY 1,234」「1234.00」「-¥500」などから円の整数を取り出す。見つからなければ nil
    static func parse(_ text: String) -> Int? {
        let s = normalize(text)
        // 数字（3桁区切りのカンマと小数点を許す）
        guard let regex = try? NSRegularExpression(pattern: "[0-9][0-9,]*(\\.[0-9]+)?") else { return nil }
        let range = NSRange(s.startIndex..., in: s)
        guard let m = regex.firstMatch(in: s, range: range), let r = Range(m.range, in: s) else { return nil }
        let raw = s[r].replacingOccurrences(of: ",", with: "")
        guard let value = Double(raw), value.isFinite else { return nil }
        let yen = Int(value.rounded())
        return yen >= 0 ? yen : nil
    }

    /// 全角の英数字・記号を半角に、￥を¥に（カタカナはそのまま）
    static func normalize(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for u in text.unicodeScalars {
            switch u.value {
            case 0xFF01...0xFF5E: out.append(Unicode.Scalar(u.value - 0xFEE0)!)
            case 0x3000: out.append(" ")
            case 0xFFE5: out.append("¥")
            default: out.append(u)
            }
        }
        return String(out)
    }
}

// MARK: - 費目の自動分類

enum Categorizer {
    /// 店名を比べやすい形にする（半角・小文字・空白なし）
    static func key(_ merchant: String) -> String {
        AmountParser.normalize(merchant)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines).joined()
    }

    /// 店名に含まれる言葉 → 費目ID（上から順に調べる）
    static let rules: [(String, [String])] = [
        ("cafe", ["スターバックス", "starbucks", "スタバ", "ドトール", "doutor", "タリーズ", "tully", "コメダ", "サンマルク", "エクセルシオール", "blue bottle", "ミスタードーナツ", "ミスド", "サーティワン", "ゴンチャ", "gong cha"]),
        ("transport", ["suica", "pasmo", "jr東日本", "jr東", "モバイルsuica", "東武", "京成", "つくばエクスプレス", "首都圏新都市鉄道", "東京メトロ", "都営", "流鉄", "バス", "タクシー", "go タクシー", "uber", "新幹線", "えきねっと", "jr", "鉄道", "駐輪"]),
        ("subscription", ["apple.com", "apple com", "itunes", "icloud", "netflix", "spotify", "youtube", "amazon prime", "プライム会費", "disney+", "u-next", "anthropic", "claude", "openai", "chatgpt", "docomo", "ドコモ", "ahamo", "povo", "ソフトバンク", "softbank", "楽天モバイル", "linemo", "uq", "google one", "google play", "adobe", "github"]),
        ("hobby", ["steam", "nintendo", "任天堂", "playstation", "プレイステーション", "ゲーム", "映画", "toho", "イオンシネマ", "109シネマズ", "カラオケ", "ラウンドワン", "round1", "アニメイト", "タワーレコード", "ヨドバシ", "ビックカメラ", "ドン・キホーテ", "ドンキ"]),
        ("study", ["紀伊國屋", "紀伊国屋", "丸善", "ジュンク堂", "三省堂", "ブックオフ", "書店", "kindle", "udemy", "大学生協", "生協"]),
        ("health", ["薬局", "クリニック", "病院", "歯科", "医院", "エニタイム", "anytime fitness", "chocozap", "チョコザップ", "ゴールドジム", "ジム", "fitness"]),
        ("fashion", ["uniqlo", "ユニクロ", "ジーユー", "zara", "h&m", "しまむら", "無印良品", "abcマート", "美容", "ヘア", "hair", "barber", "@cosme", "コスメ"]),
        ("daily", ["マツモトキヨシ", "マツキヨ", "ウエルシア", "ツルハ", "サンドラッグ", "スギ薬局", "ココカラ", "ダイソー", "daiso", "セリア", "キャンドゥ", "ニトリ", "カインズ", "ホームセンター", "100円", "amazon", "アマゾン"]),
        ("food", ["セブン", "7-eleven", "seven", "ファミリーマート", "ファミマ", "familymart", "ローソン", "lawson", "ミニストップ", "デイリーヤマザキ", "ニューデイズ", "newdays", "マクドナルド", "mcdonald", "マック", "モスバーガー", "ケンタッキー", "すき家", "吉野家", "松屋", "なか卯", "サイゼリヤ", "ガスト", "スシロー", "くら寿司", "はま寿司", "丸亀", "ココイチ", "日高屋", "大戸屋", "イオン", "aeon", "西友", "イトーヨーカドー", "ライフ", "まいばすけっと", "オーケー", "業務スーパー", "成城石井", "スーパー", "食堂", "ラーメン", "弁当", "ubereats", "uber eats", "出前館", "wolt"]),
        ("social", ["居酒屋", "鳥貴族", "磯丸", "和民", "飲み", "プレゼント"]),
        ("living", ["電気", "ガス", "水道", "東京電力", "東京ガス", "家賃"])
    ]

    /// 店名から費目を決める。覚えた組み合わせ → 言葉のルール → その他 の順
    static func category(for merchant: String, kind: TxnKind = .expense, learned: [String: String] = [:]) -> String {
        let k = key(merchant)
        if let id = learned[k] { return id }
        guard kind == .expense else {
            if k.contains("給与") || k.contains("給料") || k.contains("賞与") || k.contains("kyuyo") { return "salary" }
            return TxnCategory.otherIncomeID
        }
        // 「jr」のような短い言葉は最後に当たるよう、長い言葉から順に調べる
        var best: (id: String, length: Int)?
        for (id, words) in rules {
            for w in words {
                let wk = key(w)
                guard !wk.isEmpty, k.contains(wk) else { continue }
                if best == nil || wk.count > best!.length { best = (id, wk.count) }
            }
        }
        return best?.id ?? TxnCategory.otherID
    }
}

// MARK: - 銀行・カードの通知文

/// 入出金通知のメールや SMS を貼り付けたときに、日付・金額・入金か出金か・相手を読み取る
enum NoticeParser {
    struct Draft: Equatable {
        var date: Date?
        var amount: Int
        var kind: TxnKind
        var merchant: String
    }

    static let incomeWords = ["入金", "お預入", "預入", "振込入金", "お振込みがありました", "給与", "賞与", "受取", "返金", "払戻"]
    static let expenseWords = ["出金", "お引出", "引出", "引落", "引き落", "ご利用", "利用金額", "お支払", "支払", "振込出金", "デビット", "購入", "決済"]
    static let partnerLabels = ["ご利用先", "ご利用店舗", "利用店舗", "利用先", "加盟店", "お支払先", "支払先", "摘要", "お取引内容", "取引内容", "内容", "振込元", "依頼人", "お振込人", "振込人", "店舗名", "店名"]

    static func parse(_ text: String, now: Date = Date()) -> Draft? {
        let s = AmountParser.normalize(text)
        guard let amount = amount(in: s) else { return nil }
        let kind = detectKind(s)
        let date = detectDate(s, now: now)
        let merchant = detectPartner(text) ?? (kind == .income ? "入金" : "出金")
        return Draft(date: date, amount: amount, kind: kind, merchant: merchant)
    }

    /// 「1,234円」「¥1,234」「金額：1,234」を優先して探す
    static func amount(in s: String) -> Int? {
        let patterns = [
            "(?:金額|ご利用額|利用金額|お支払金額|入金額|出金額|お取引金額)[^0-9¥\\n]{0,6}¥?\\s*([0-9][0-9,]*)",
            "¥\\s*([0-9][0-9,]*)",
            "([0-9][0-9,]*)\\s*円"
        ]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p) else { continue }
            let range = NSRange(s.startIndex..., in: s)
            if let m = re.firstMatch(in: s, range: range), m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: s),
               let v = Int(s[r].replacingOccurrences(of: ",", with: "")), v > 0 {
                return v
            }
        }
        return nil
    }

    static func detectKind(_ s: String) -> TxnKind {
        func firstIndex(_ words: [String]) -> String.Index? {
            words.compactMap { s.range(of: $0)?.lowerBound }.min()
        }
        switch (firstIndex(incomeWords), firstIndex(expenseWords)) {
        case let (i?, e?): return i < e ? .income : .expense
        case (_?, nil): return .income
        default: return .expense
        }
    }

    static func detectDate(_ s: String, now: Date) -> Date? {
        let cal = JST.gregorian
        let nowDay = DayKey(now)
        // 2026/10/14 13:05、2026年10月14日 13時05分、10/14 13:05
        let patterns: [(String, Bool)] = [
            ("(20[0-9]{2})[/年.-]\\s*([0-9]{1,2})[/月.-]\\s*([0-9]{1,2})日?(?:[^0-9]{0,6}([0-9]{1,2})[:時]([0-9]{2}))?", true),
            ("(?<![0-9])([0-9]{1,2})[/月]([0-9]{1,2})日?(?:[^0-9]{0,6}([0-9]{1,2})[:時]([0-9]{2}))?", false)
        ]
        for (p, hasYear) in patterns {
            guard let re = try? NSRegularExpression(pattern: p) else { continue }
            guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { continue }
            func group(_ i: Int) -> Int? {
                guard i < m.numberOfRanges, let r = Range(m.range(at: i), in: s) else { return nil }
                return Int(s[r])
            }
            var c = DateComponents()
            c.timeZone = JST.timeZone
            if hasYear {
                c.year = group(1); c.month = group(2); c.day = group(3); c.hour = group(4) ?? 12; c.minute = group(5) ?? 0
            } else {
                c.month = group(1); c.day = group(2); c.hour = group(3) ?? 12; c.minute = group(4) ?? 0
                // 年が書いていなければ、未来にならない年
                c.year = nowDay.year
                if let m = c.month, let d = c.day, (m > nowDay.month || (m == nowDay.month && d > nowDay.day)) {
                    c.year = nowDay.year - 1
                }
            }
            guard let month = c.month, (1...12).contains(month), let day = c.day, (1...31).contains(day) else { continue }
            if let d = cal.date(from: c) { return d }
        }
        return nil
    }

    static func detectPartner(_ s: String) -> String? {
        let lines = s.components(separatedBy: .newlines)
        for label in partnerLabels {
            for line in lines {
                guard let r = line.range(of: label) else { continue }
                var rest = String(line[r.upperBound...])
                rest = rest.trimmingCharacters(in: CharacterSet(charactersIn: ":：　 \t】]）)「」"))
                // 金額や日付だけの行は除く
                if rest.isEmpty || AmountParser.parse(rest) != nil && rest.count < 12 && rest.rangeOfCharacter(from: .letters) == nil { continue }
                if rest.count > 40 { rest = String(rest.prefix(40)) }
                return rest
            }
        }
        return nil
    }
}

// MARK: - CSV（銀行・カードの明細）

enum CSVImporter {
    struct Row: Equatable {
        var date: Date
        var amount: Int
        var kind: TxnKind
        var merchant: String
    }

    /// UTF-8 と Shift_JIS のどちらでも読む
    static func decode(_ data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .shiftJIS) { return s }
        return String(data: data, encoding: .japaneseEUC)
    }

    /// 1行をカンマで分ける（"" で囲まれた中のカンマはそのまま）
    static func split(_ line: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var quoted = false
        var chars = Array(line)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "\"" {
                if quoted, i + 1 < chars.count, chars[i + 1] == "\"" { cur.append("\""); i += 1 } else { quoted.toggle() }
            } else if ch == "," && !quoted {
                out.append(cur); cur = ""
            } else {
                cur.append(ch)
            }
            i += 1
        }
        out.append(cur)
        chars.removeAll()
        return out.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static let dateHeaders = ["日付", "取引日", "年月日", "利用日", "ご利用日", "お取引日", "date"]
    static let memoHeaders = ["摘要", "内容", "お取引内容", "取引内容", "ご利用店名", "利用店名", "ご利用先", "利用先", "店名", "明細", "description", "メモ"]
    static let outHeaders = ["出金", "お引出", "引出", "お支払", "支払金額", "ご利用金額", "利用金額", "出金額", "引落", "withdrawal"]
    static let inHeaders = ["入金", "お預入", "預入", "入金額", "deposit"]
    static let amountHeaders = ["金額", "amount"]

    static func parse(_ text: String) -> [Row] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        // 見出しの行を探す（最初の10行まで）
        func find(_ headers: [String], in cols: [String]) -> Int? {
            cols.firstIndex { c in headers.contains { c.lowercased().contains($0) } }
        }
        var header: (index: Int, date: Int, memo: Int?, out: Int?, inn: Int?, amount: Int?)?
        for (i, line) in lines.prefix(10).enumerated() {
            let cols = split(line)
            if let d = find(dateHeaders, in: cols) {
                let o = find(outHeaders, in: cols)
                let n = find(inHeaders, in: cols)
                let a = (o == nil && n == nil) ? find(amountHeaders, in: cols) : nil
                if o != nil || n != nil || a != nil {
                    header = (i, d, find(memoHeaders, in: cols), o, n, a)
                    break
                }
            }
        }
        guard let h = header else { return [] }
        var rows: [Row] = []
        for line in lines.dropFirst(h.index + 1) {
            let cols = split(line)
            guard h.date < cols.count, let date = NoticeParser.detectDate(cols[h.date], now: Date()) ?? parseCompactDate(cols[h.date]) else { continue }
            let memo = h.memo.flatMap { $0 < cols.count ? cols[$0] : nil } ?? ""
            func value(_ i: Int?) -> Int? {
                guard let i, i < cols.count else { return nil }
                let t = cols[i]
                guard let v = AmountParser.parse(t), v > 0 else { return nil }
                return t.contains("-") || t.contains("−") || t.contains("△") ? -v : v
            }
            if let v = value(h.out) {
                rows.append(Row(date: date, amount: abs(v), kind: v < 0 ? .income : .expense, merchant: memo))
            } else if let v = value(h.inn) {
                rows.append(Row(date: date, amount: abs(v), kind: .income, merchant: memo))
            } else if let v = value(h.amount) {
                // 金額の列が1つだけなら、マイナスを収入として扱う（カード明細の返金など）
                rows.append(Row(date: date, amount: abs(v), kind: v < 0 ? .income : .expense, merchant: memo))
            }
        }
        return rows
    }

    /// 20261014 のような日付
    static func parseCompactDate(_ s: String) -> Date? {
        let digits = s.filter(\.isNumber)
        guard digits.count == 8, let v = Int(digits) else { return nil }
        let c = DateComponents(timeZone: JST.timeZone, year: v / 10000, month: v / 100 % 100, day: v % 100, hour: 12)
        guard (1...12).contains(c.month!), (1...31).contains(c.day!) else { return nil }
        return JST.gregorian.date(from: c)
    }
}
