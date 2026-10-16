import SwiftUI
import UIKit

/// 取引1件の行
struct TxnRow: View {
    let txn: Txn
    let category: TxnCategory
    let now: Date
    var showsDate = false

    var body: some View {
        HStack(spacing: 12) {
            CategoryBadge(symbol: category.symbol, color: category.color, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(txn.merchant.isEmpty ? category.name : txn.merchant)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(showsDate ? Fmt.when(txn.date, now: now) : Fmt.time(txn.date))
                    Text("·")
                    Text(category.name)
                    if !txn.account.isEmpty {
                        Text("·")
                        Text(txn.account).lineLimit(1)
                    }
                    if txn.source == .applePay {
                        Image(systemName: "wave.3.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            if txn.needsAmount {
                Text("金額を入力")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(Theme.accent, in: Capsule())
            } else {
                Text(txn.kind == .income ? "+\(Fmt.yen(txn.amount))" : Fmt.yen(txn.amount))
                    .font(Theme.number(19, weight: .bold))
                    .foregroundStyle(txn.kind == .income ? Theme.income : Theme.ink)
                    .monospacedDigit()
            }
        }
        .contentShape(Rectangle())
    }
}

/// 期間の切り替え（‹ 2026年10月 ›）
struct PeriodSwitcher: View {
    @Binding var period: Period
    @Binding var direction: CGFloat
    let current: Period

    var body: some View {
        HStack(spacing: 10) {
            Button { move(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(GlassCircleButtonStyle(size: 38))
            VStack(spacing: 1) {
                Text(period.title)
                    .font(.system(size: 19, weight: .heavy).width(.condensed))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                Text(period.rangeLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity)
            .onTapGesture { if period != current { jump(to: current) } }
            Button { move(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(GlassCircleButtonStyle(size: 38))
                .disabled(period >= current)
                .opacity(period >= current ? 0.35 : 1)
        }
    }

    private func move(_ n: Int) {
        UISelectionFeedbackGenerator().selectionChanged()
        direction = CGFloat(n)
        withAnimation(Motion.cinematicFast) { period = period.adding(n) }
    }

    private func jump(to p: Period) {
        direction = p > period ? 1 : -1
        withAnimation(Motion.cinematicFast) { period = p }
    }
}

/// 画面上の大きな見出し
struct ScreenHeader: View {
    let title: String
    var subtitle: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
            Text(title)
                .font(.system(size: 34, weight: .heavy).width(.condensed))
                .foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 小さな数字のまとまり
struct StatTile: View {
    let title: String
    let value: String
    var tint: Color = Theme.ink
    var caption: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(Theme.number(21, weight: .bold))
                .foregroundStyle(tint)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.faint)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// レシートの区切り（点線）
struct DashedRule: View {
    var body: some View {
        Line()
            .stroke(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .frame(height: 1)
    }

    struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return p
        }
    }
}

/// 費目の選択チップ
struct CategoryChip: View {
    let category: TxnCategory
    let selected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: category.symbol)
                .font(.system(size: 12, weight: .bold))
            Text(category.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(selected ? Theme.onAccent : category.color)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(selected ? category.color : category.color.opacity(0.12), in: Capsule())
        .animation(Motion.snappy, value: selected)
    }
}

/// 右下に浮かぶ「＋」ボタン
struct AddButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 58, height: 58)
                .liquidGlass(in: Circle(), tint: Theme.accent.opacity(0.95))
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityLabel("記録する")
        .padding(.trailing, 20)
        .padding(.bottom, 14)
    }
}

/// 何もないときの案内
struct EmptyNote: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.faint)
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}
