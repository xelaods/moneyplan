import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    @AppStorage("calendarBridge") private var calendarBridge = true

    @State private var budgetText = ""
    @State private var share: ShareItem?
    @State private var importing: ImportKind?
    @State private var csvRows: [CSVImporter.Row]?
    @State private var message: String?
    @State private var confirmErase = false

    enum ImportKind: Identifiable { case csv, backup; var id: Self { self } }

    var body: some View {
        NavigationStack {
            Form {
                budgetSection
                autoSection
                widgetSection
                dataSection
                Section("外観") {
                    Picker("画面の色", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                }
                Section {
                    LabeledContent("バージョン", value: version)
                    LabeledContent("記録の件数", value: "\(store.file.txns.count)件")
                } footer: {
                    Text("データはこの iPhone の中だけに保存されます。どこにも送信しません。")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("設定")
            .onAppear { budgetText = store.budget.monthly > 0 ? String(store.budget.monthly) : "" }
            .sheet(item: $share) { item in
                ActivityView(items: [item.url]).presentationDetents([.medium, .large])
            }
            .sheet(isPresented: Binding(get: { csvRows != nil }, set: { if !$0 { csvRows = nil } })) {
                if let rows = csvRows {
                    NavigationStack { CSVPreviewView(rows: rows) { message = $0 } }
                        .presentationCornerRadius(28)
                }
            }
            .fileImporter(isPresented: Binding(get: { importing != nil }, set: { if !$0 { importing = nil } }),
                          allowedContentTypes: importing == .backup ? [.json] : [.commaSeparatedText, .plainText, .text, .data]) { result in
                handleImport(result)
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
            .confirmationDialog("すべての記録を削除しますか？", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("すべて削除", role: .destructive) { store.eraseAll() }
            } message: {
                Text("予算や覚えた分類も初期状態に戻ります。元に戻せません。")
            }
        }
    }

    // MARK: 予算

    private var budgetSection: some View {
        Section {
            HStack {
                Text("1か月の予算")
                Spacer()
                Text("¥").foregroundStyle(Theme.muted)
                TextField("なし", text: $budgetText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(Theme.number(20, weight: .bold))
                    .frame(maxWidth: 140)
                    .onChange(of: budgetText) { _, v in
                        let digits = v.filter(\.isNumber)
                        if digits != v { budgetText = digits }
                        var b = store.budget
                        b.monthly = Int(digits) ?? 0
                        if b != store.budget { store.setBudget(b) }
                    }
            }
            Picker("月の始まり", selection: Binding(get: { store.budget.startDay }, set: { v in
                var b = store.budget
                b.startDay = v
                store.setBudget(b)
            })) {
                Text("1日（月末まで）").tag(1)
                ForEach(2...28, id: \.self) { d in Text("\(d)日（翌月\(d - 1)日まで）").tag(d) }
            }
            NavigationLink {
                CategoryBudgetsView()
            } label: {
                LabeledContent("費目ごとの予算", value: store.budget.byCategory.isEmpty ? "なし" : "\(store.budget.byCategory.count)件")
            }
        } header: {
            Text("予算")
        } footer: {
            Text("給料日に合わせたいときは、月の始まりを給料日にしてください（25日なら 10/25〜11/24 が「11月」）。")
        }
    }

    // MARK: 自動で記録

    private var autoSection: some View {
        Section {
            NavigationLink {
                ShortcutGuideView()
            } label: {
                HStack {
                    Label("Apple Pay を自動で記録", systemImage: "wave.3.right")
                    Spacer()
                    Text(store.lastApplePay.map { "最終 \(Fmt.when($0, now: store.now))" } ?? "未設定")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                }
            }
            NavigationLink {
                IntentLogView()
            } label: {
                LabeledContent {
                    Text("\(IntentLog.all().count)件")
                } label: {
                    Label("ショートカットから受け取った内容", systemImage: "list.bullet.clipboard")
                }
            }
            NavigationLink {
                NoticeImportView()
            } label: {
                Label("銀行の通知文から記録", systemImage: "building.columns")
            }
            Button {
                importing = .csv
            } label: {
                Label("明細の CSV を読み込む", systemImage: "tablecells")
            }
            NavigationLink {
                LearnedView()
            } label: {
                LabeledContent {
                    Text("\(store.file.learned.count)件")
                } label: {
                    Label("覚えた分類", systemImage: "brain")
                }
            }
        } header: {
            Text("自動で記録")
        } footer: {
            Text("記録の費目を直すと、そのお店は次から同じ費目になります。")
        }
    }

    // MARK: ウィジェット

    private var widgetSection: some View {
        Section {
            HStack {
                Text("ウィジェットとの連携")
                Spacer()
                switch store.widgetBridge {
                case .appGroup:
                    Label("App Group", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.income)
                case .calendar:
                    Label("カレンダー経由", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.income)
                case .none:
                    Label("未接続", systemImage: "exclamationmark.circle.fill").foregroundStyle(Theme.warning)
                }
            }
            .font(.system(size: 14, weight: .semibold))
            if !SharedStore.isShared {
                Toggle("カレンダー経由で渡す", isOn: $calendarBridge)
                    .onChange(of: calendarBridge) { _, on in
                        if on { store.publishSummary() } else { CalendarSummaryStore.clear() }
                        store.reload()
                    }
                if calendarBridge && store.calendarStatus != .fullAccess {
                    Button {
                        if CalendarSummaryStore.denied, let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        } else {
                            Task { await store.requestCalendarAccess() }
                        }
                    } label: {
                        Label(CalendarSummaryStore.denied ? "設定アプリでカレンダーを許可" : "カレンダーへのアクセスを許可", systemImage: "calendar.badge.plus")
                    }
                }
            }
            Button {
                store.publishSummary()
                message = "ウィジェットを更新しました"
            } label: {
                Label("ウィジェットを今すぐ更新", systemImage: "arrow.clockwise")
            }
        } header: {
            Text("ウィジェット")
        } footer: {
            Text(SharedStore.isShared
                 ? "App Group でアプリとウィジェットがデータを共有しています。"
                 : "署名に App Group が入っていないため、カレンダーの 2001年1月2日 に集計メモを1件だけ保存してウィジェットに渡します（Shift Note と同じ方法）。ふだんの予定には表示されません。")
        }
    }

    // MARK: データ

    private var dataSection: some View {
        Section {
            Button {
                share = ShareItem(url: Exporter.csv(store.file))
            } label: {
                Label("CSV で書き出す", systemImage: "square.and.arrow.up")
            }
            Button {
                if let data = store.backupData { share = ShareItem(url: Exporter.write(data, name: "MoneyPlan-backup-\(Fmt.full(Date()).replacingOccurrences(of: "/", with: "")).json")) }
            } label: {
                Label("バックアップを保存", systemImage: "externaldrive")
            }
            Button {
                importing = .backup
            } label: {
                Label("バックアップから戻す", systemImage: "arrow.counterclockwise")
            }
            Button(role: .destructive) {
                confirmErase = true
            } label: {
                Label("すべて削除", systemImage: "trash")
            }
        } header: {
            Text("データ")
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        let kind = importing
        importing = nil
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { message = "ファイルを読み込めませんでした"; return }
        switch kind {
        case .backup:
            message = store.restore(data) ? "バックアップから戻しました" : "MoneyPlan のバックアップではないようです"
        default:
            guard let text = CSVImporter.decode(data) else { message = "文字コードを判別できませんでした"; return }
            let rows = CSVImporter.parse(text)
            if rows.isEmpty {
                message = "日付と金額の列を見つけられませんでした。銀行やカード会社のサイトから書き出した CSV を選んでください"
            } else {
                csvRows = rows
            }
        }
    }

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v)（\(b)）"
    }
}

struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.path }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

enum Exporter {
    static func write(_ data: Data, name: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? data.write(to: url, options: .atomic)
        return url
    }

    /// Excel でも文字化けしないよう、先頭に BOM を付けた UTF-8
    static func csv(_ file: LedgerFile) -> URL {
        let ledger = Ledger(file: file)
        func esc(_ s: String) -> String {
            s.contains(",") || s.contains("\"") || s.contains("\n") ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
        }
        var lines = ["日付,時刻,種類,金額,費目,店名・内容,支払い方法,メモ,記録元"]
        for t in file.txns.sorted(by: { $0.date < $1.date }) {
            lines.append([Fmt.full(t.date), Fmt.time(t.date), t.kind.label, String(t.amount), ledger.category(t.categoryID).name,
                          t.merchant, t.account, t.note, t.source.label].map(esc).joined(separator: ","))
        }
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(lines.joined(separator: "\r\n").data(using: .utf8) ?? Data())
        return write(data, name: "MoneyPlan-\(Fmt.full(Date()).replacingOccurrences(of: "/", with: "")).csv")
    }
}

// MARK: - 費目ごとの予算

struct CategoryBudgetsView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let l = store.ledger
        let spent = Dictionary(uniqueKeysWithValues: l.byCategory(in: l.current).map { ($0.category.id, $0.amount) })
        Form {
            Section {
                ForEach(store.expenseCategories) { c in
                    HStack(spacing: 10) {
                        CategoryBadge(symbol: c.symbol, color: c.color, size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.name)
                            Text("今月 \(Fmt.yen(spent[c.id] ?? 0))")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Text("¥").foregroundStyle(Theme.muted)
                        TextField("なし", text: Binding(
                            get: { store.budget.byCategory[c.id].map(String.init) ?? "" },
                            set: { store.setCategoryBudget(c.id, Int($0.filter(\.isNumber)) ?? 0) }))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(Theme.number(18, weight: .bold))
                            .frame(maxWidth: 110)
                    }
                }
            } footer: {
                Text("予算を入れた費目だけ、分析タブに進み具合が出ます。")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("費目ごとの予算")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 覚えた分類

struct LearnedView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        List {
            if store.file.learned.isEmpty {
                EmptyNote(symbol: "brain", title: "まだありません", message: "記録の費目を直すと、そのお店と費目の組み合わせがここに追加されます")
                    .listRowBackground(Color.clear)
            }
            ForEach(store.file.learned.sorted { $0.key < $1.key }, id: \.key) { key, id in
                let c = store.category(id)
                HStack {
                    Text(key).lineLimit(1)
                    Spacer()
                    CategoryChip(category: c, selected: false)
                }
            }
            .onDelete { idx in
                let keys = store.file.learned.sorted { $0.key < $1.key }.map(\.key)
                for i in idx { store.forget(key: keys[i]) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("覚えた分類")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - ショートカットの受信ログ

struct IntentLogView: View {
    @State private var entries = IntentLog.all()

    var body: some View {
        List {
            if entries.isEmpty {
                EmptyNote(symbol: "tray", title: "まだ何も届いていません",
                          message: "Apple Pay で払ってもここに何も出ないときは、オートメーションが動いていません。ショートカットアプリの「オートメーション」で、カードと「すぐに実行」を確認してください。")
                    .listRowBackground(Color.clear)
            }
            ForEach(entries) { e in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(Fmt.full(e.date)) \(Fmt.time(e.date))")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.muted)
                    row("金額", e.amount)
                    row("店名", e.merchant)
                    row("カード", e.card)
                    Text(e.result)
                        .font(.system(size: 12))
                        .foregroundStyle(e.result.contains("0円") ? Theme.accent : Theme.income)
                }
                .padding(.vertical, 4)
                .textSelection(.enabled)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("受け取った内容")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !entries.isEmpty {
                Button("消去") { IntentLog.clear(); entries = [] }
            }
        }
        .refreshable { entries = IntentLog.all() }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .frame(width: 48, alignment: .leading)
            Text(value.isEmpty ? "（空）" : value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(value.isEmpty ? Theme.accent : Theme.ink)
                .lineLimit(4)
        }
    }
}
