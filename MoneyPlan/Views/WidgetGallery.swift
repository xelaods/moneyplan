import SwiftUI
import WidgetKit

/// ウィジェットの見本（起動引数 -gallery で表示。見た目の確認用）
struct WidgetGallery: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let s = store.ledger.summary()
        let now = store.now
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    tile(.systemSmall) { MonthWidgetView(summary: s, now: now, family: .systemSmall) }
                    tile(.systemSmall) { CategoryWidgetView(summary: s, now: now, family: .systemSmall) }
                }
                tile(.systemMedium) { MonthWidgetView(summary: s, now: now, family: .systemMedium) }
                tile(.systemMedium) { RecentWidgetView(summary: s, now: now, family: .systemMedium) }
                tile(.systemMedium) { CategoryWidgetView(summary: s, now: now, family: .systemMedium) }
                tile(.systemLarge) { RecentWidgetView(summary: s, now: now, family: .systemLarge) }
                tile(.systemLarge) { CategoryWidgetView(summary: s, now: now, family: .systemLarge) }
                HStack(spacing: 14) {
                    accessory(width: 160) { MonthWidgetView(summary: s, now: now, family: .accessoryRectangular) }
                    accessory(width: 72) { MonthWidgetView(summary: s, now: now, family: .accessoryCircular) }
                }
            }
            .padding(16)
        }
        .background(Color(white: 0.45).ignoresSafeArea())
    }

    private func size(_ family: WidgetFamily) -> CGSize {
        switch family {
        case .systemSmall: return CGSize(width: 170, height: 170)
        case .systemMedium: return CGSize(width: 354, height: 170)
        default: return CGSize(width: 354, height: 376)
        }
    }

    private func tile<V: View>(_ family: WidgetFamily, @ViewBuilder _ content: () -> V) -> some View {
        let s = size(family)
        return content()
            .padding(16)
            .frame(width: s.width, height: s.height)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func accessory<V: View>(width: CGFloat, @ViewBuilder _ content: () -> V) -> some View {
        content()
            .foregroundStyle(.white)
            .frame(width: width, height: 72, alignment: .leading)
            .padding(.horizontal, 8)
            .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
