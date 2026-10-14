import WidgetKit
import SwiftUI

@main
struct MoneyPlanWidgets: WidgetBundle {
    var body: some Widget {
        MonthWidget()
        RecentWidget()
        CategoryWidget()
    }
}

// MARK: - データ

enum LoadState {
    case ready(WidgetSummary)
    case message(String)
}

struct SummaryEntry: TimelineEntry {
    let date: Date
    let state: LoadState
}

struct SummaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> SummaryEntry {
        SummaryEntry(date: Date(), state: .ready(Sample.summary()))
    }

    func getSnapshot(in context: Context, completion: @escaping (SummaryEntry) -> Void) {
        let now = Date()
        if context.isPreview {
            completion(SummaryEntry(date: now, state: .ready(Sample.summary(now: now))))
            return
        }
        switch load(now: now) {
        case .message: completion(SummaryEntry(date: now, state: .ready(Sample.summary(now: now))))
        case let state: completion(SummaryEntry(date: now, state: state))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SummaryEntry>) -> Void) {
        let now = Date()
        let state = load(now: now)
        // 日付の変わり目（今日の支出・1日あたりを更新）と、30分ごと
        let midnight = DayKey(now).adding(days: 1).date
        let next = min(midnight, now.addingTimeInterval(30 * 60))
        var entries = [SummaryEntry(date: now, state: state)]
        if midnight > now, midnight <= now.addingTimeInterval(30 * 60), case .ready(let s) = state {
            entries.append(SummaryEntry(date: midnight, state: .ready(s.adjusted(for: midnight))))
        }
        completion(Timeline(entries: entries, policy: .after(next.addingTimeInterval(1))))
    }

    private func load(now: Date) -> LoadState {
        if let s = SharedStore.loadSummary() {
            return .ready(s.adjusted(for: now))
        }
        if !SharedStore.isShared && !CalendarSummaryStore.hasAccess {
            return .message("アプリの設定で「カレンダーへのアクセスを許可」すると表示されます")
        }
        return .message("アプリを開くと表示されます")
    }
}

extension View {
    func widgetBackground() -> some View {
        containerBackground(for: .widget) { Theme.card }
    }
}

struct EntryView<Content: View>: View {
    let entry: SummaryEntry
    @ViewBuilder let content: (WidgetSummary, Date, WidgetFamily) -> Content
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch entry.state {
        case .message(let text): WidgetMessageView(text: text, family: family)
        case .ready(let s): content(s, entry.date, family)
        }
    }
}

// MARK: - ウィジェット

struct MonthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Month", provider: SummaryProvider()) { entry in
            EntryView(entry: entry) { s, now, family in
                MonthWidgetView(summary: s, now: now, family: family)
            }
            .widgetBackground()
            .widgetURL(URL(string: "moneyplan://home"))
        }
        .configurationDisplayName("今月の支出")
        .description("今月使った金額、予算の残り、1日に使える額。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct RecentWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Recent", provider: SummaryProvider()) { entry in
            EntryView(entry: entry) { s, now, family in
                RecentWidgetView(summary: s, now: now, family: family)
            }
            .widgetBackground()
            .widgetURL(URL(string: "moneyplan://ledger"))
        }
        .configurationDisplayName("最近の記録")
        .description("Apple Pay などで記録した最近の支出。＋からすぐ手入力できます。")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct CategoryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Category", provider: SummaryProvider()) { entry in
            EntryView(entry: entry) { s, now, family in
                CategoryWidgetView(summary: s, now: now, family: family)
            }
            .widgetBackground()
            .widgetURL(URL(string: "moneyplan://analysis"))
        }
        .configurationDisplayName("費目の内訳")
        .description("今月の支出を費目ごとに。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
