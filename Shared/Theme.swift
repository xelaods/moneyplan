import SwiftUI
import UIKit

/// 色と文字のルール。
/// レシートの紙（paper）と印字のインク（ink）を基本に、支出は朱肉の朱色、収入は通帳の緑。
/// 費目ごとの色は TxnCategory が持つ。
enum Theme {
    static let paper = dynamic(light: 0xF4F1EA, dark: 0x0F0F10)
    static let card = dynamic(light: 0xFFFEFB, dark: 0x1B1B1D)
    static let ink = dynamic(light: 0x1A1918, dark: 0xF4F1EA)
    static let muted = dynamic(light: 0x6E6A63, dark: 0x9B978F)
    static let faint = dynamic(light: 0xA8A39A, dark: 0x5E5B56)
    static let line = dynamic(light: 0xE4DFD4, dark: 0x2B2A28)
    static let fill = dynamic(light: 0xECE7DC, dark: 0x252422)

    /// 朱色（支出・アクセント）
    static let accent = dynamic(light: 0xD93E29, dark: 0xFF6F58)
    /// 通帳の緑（収入・予算内）
    static let income = dynamic(light: 0x1E7F55, dark: 0x45C487)
    static let warning = dynamic(light: 0xC98205, dark: 0xF2B53C)
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x0F0F10)
    static let sunday = dynamic(light: 0xD93E29, dark: 0xFF6F58)
    static let saturday = dynamic(light: 0x2F64D6, dark: 0x6C95F2)

    /// 数字：細長い太字（レシートの合計欄のような字面）
    static func number(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }

    /// 小見出し
    static let label = Font.system(size: 12, weight: .bold).width(.condensed)

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    static func weekdayColor(_ weekday: Int) -> Color {
        switch weekday {
        case 1: return sunday
        case 7: return saturday
        default: return ink
        }
    }

    /// 予算の使い具合による色（目安より少ない＝緑、少し多い＝黄、超えた＝朱）
    static func paceColor(spent: Int, target: Int, budget: Int) -> Color {
        guard budget > 0 else { return ink }
        if spent > budget { return accent }
        if spent > Int(Double(target) * 1.1) { return warning }
        return income
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

extension TxnCategory {
    var color: Color { Theme.dynamic(light: lightHex, dark: darkHex) }
}

extension WidgetSummary.Slice {
    var color: Color { Theme.dynamic(light: light, dark: dark) }
}

extension WidgetSummary.Item {
    var color: Color { Theme.dynamic(light: light, dark: dark) }
}

// MARK: - 共通の部品（アプリとウィジェットで使う）

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.label)
            .tracking(1.2)
            .foregroundStyle(Theme.muted)
    }
}

/// 金額の大きな表示（数字が変わるときにめくれる）
struct Amount: View {
    let value: Int
    var size: CGFloat = 44
    var color: Color = Theme.ink
    var sign: String = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            if !sign.isEmpty {
                Text(sign)
                    .font(Theme.number(size * 0.6, weight: .bold))
                    .foregroundStyle(color)
            }
            Text("¥")
                .font(Theme.number(size * 0.55, weight: .bold))
                .foregroundStyle(color.opacity(0.6))
            Text(Fmt.number(value))
                .font(Theme.number(size, weight: .black))
                .foregroundStyle(color)
                .contentTransition(.numericText(value: Double(value)))
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
}

/// 費目のアイコン（色付きの角丸）
struct CategoryBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .bold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

/// 予算バー：使った分（色）と、今日までの目安の位置（縦線）
struct BudgetBar: View {
    let spent: Int
    let budget: Int
    let target: Int
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let ratio = budget > 0 ? min(1, Double(spent) / Double(budget)) : 0
            let t = budget > 0 ? min(1, Double(target) / Double(budget)) : 0
            let color = Theme.paceColor(spent: spent, target: target, budget: budget)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fill)
                Capsule().fill(color)
                    .frame(width: spent > 0 ? max(height, w * ratio) : 0)
                if budget > 0 {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Theme.ink.opacity(0.55))
                        .frame(width: 2, height: height + 6)
                        .offset(x: w * t - 1)
                }
            }
        }
        .frame(height: height)
    }
}

/// 費目の割合の帯（横に積み上げ）
struct StackBar: View {
    let parts: [(Color, Int)]
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { g in
            let total = max(1, parts.reduce(0) { $0 + $1.1 })
            let gap: CGFloat = parts.count > 1 ? 2 : 0
            let usable = g.size.width - gap * CGFloat(max(0, parts.count - 1))
            HStack(spacing: gap) {
                if parts.isEmpty {
                    Capsule().fill(Theme.fill)
                } else {
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                            .fill(p.0)
                            .frame(width: max(height * 0.6, usable * CGFloat(p.1) / CGFloat(total)))
                    }
                }
            }
        }
        .frame(height: height)
    }
}

/// 費目の割合のドーナツ
struct Donut: View {
    let parts: [(Color, Int)]
    var lineWidth: CGFloat = 14

    var body: some View {
        let total = Double(max(1, parts.reduce(0) { $0 + $1.1 }))
        ZStack {
            Circle().stroke(Theme.fill, lineWidth: lineWidth)
            ForEach(Array(segments(total: total).enumerated()), id: \.offset) { _, seg in
                Circle()
                    .trim(from: seg.from, to: seg.to)
                    .stroke(seg.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(lineWidth / 2)
    }

    private func segments(total: Double) -> [(from: CGFloat, to: CGFloat, color: Color)] {
        var start = 0.0
        let gap = parts.count > 1 ? 0.006 : 0
        return parts.map { p in
            let len = Double(p.1) / total
            defer { start += len }
            return (CGFloat(start + gap), CGFloat(max(start + gap, start + len - gap)), p.0)
        }
    }
}

/// 累計の折れ線（今日まで）と、予算どおりの線（点線）
struct PaceChart: View {
    let cumulative: [Int]
    let days: Int
    let budget: Int
    var lineWidth: CGFloat = 2.5
    var showsBudgetLine = true

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let top = Double(max(budget, cumulative.last ?? 0, 1)) * 1.08
            let x = { (i: Int) -> CGFloat in days > 1 ? w * CGFloat(i) / CGFloat(days - 1) : 0 }
            let y = { (v: Int) -> CGFloat in h - h * CGFloat(Double(v) / top) }
            let color = Theme.paceColor(spent: cumulative.last ?? 0,
                                        target: budget > 0 ? Int(Double(budget) * Double(cumulative.count) / Double(max(1, days))) : 0,
                                        budget: budget)
            ZStack(alignment: .topLeading) {
                if showsBudgetLine && budget > 0 {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: h))
                        p.addLine(to: CGPoint(x: w, y: y(budget)))
                    }
                    .stroke(Theme.faint, style: StrokeStyle(lineWidth: 1.2, dash: [3, 4]))
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y(budget)))
                        p.addLine(to: CGPoint(x: w, y: y(budget)))
                    }
                    .stroke(Theme.line, lineWidth: 1)
                }
                if !cumulative.isEmpty {
                    // 塗り
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: h))
                        for (i, v) in cumulative.enumerated() { p.addLine(to: CGPoint(x: x(i), y: y(v))) }
                        p.addLine(to: CGPoint(x: x(cumulative.count - 1), y: h))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.22), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                    // 線（日ごとの階段）
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y(cumulative[0])))
                        for (i, v) in cumulative.enumerated() where i > 0 {
                            p.addLine(to: CGPoint(x: x(i), y: y(cumulative[i - 1])))
                            p.addLine(to: CGPoint(x: x(i), y: y(v)))
                        }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                    Circle()
                        .fill(color)
                        .frame(width: lineWidth * 3, height: lineWidth * 3)
                        .position(x: x(cumulative.count - 1), y: y(cumulative.last ?? 0))
                }
            }
        }
    }
}
