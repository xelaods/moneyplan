import SwiftUI

/// 動きのルール：ピントが合いながら現れ、ゆっくり減速して止まる
enum Motion {
    static let cinematic = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.9)
    static let cinematicFast = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.5)
    static let snappy = Animation.spring(response: 0.38, dampingFraction: 0.82)
}

struct FocusPull: ViewModifier {
    var blur: CGFloat
    var x: CGFloat = 0
    var y: CGFloat = 0
    var scale: CGFloat = 1
    var opacity: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .scaleEffect(scale)
            .offset(x: x, y: y)
            .opacity(opacity)
    }
}

extension AnyTransition {
    static var cinematic: AnyTransition {
        .modifier(active: FocusPull(blur: 12, scale: 1.03, opacity: 0),
                  identity: FocusPull(blur: 0, opacity: 1))
    }

    /// 前後の月・年の切り替え。direction が +1 なら右から入る
    static func cinematicSlide(_ direction: CGFloat) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(active: FocusPull(blur: 8, x: 50 * direction, scale: 0.98, opacity: 0),
                                 identity: FocusPull(blur: 0, opacity: 1)),
            removal: .modifier(active: FocusPull(blur: 8, x: -50 * direction, scale: 0.98, opacity: 0),
                               identity: FocusPull(blur: 0, opacity: 1))
        )
    }
}

/// 画面を開いたとき、上から順にピントが合いながら浮かび上がる
struct CinematicReveal: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .blur(radius: shown || reduceMotion ? 0 : 10)
            .offset(y: shown || reduceMotion ? 0 : 24)
            .scaleEffect(shown || reduceMotion ? 1 : 0.97, anchor: .top)
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(Motion.cinematic.delay(Double(index) * 0.06)) { shown = true }
            }
    }
}

extension View {
    func cinematicReveal(_ index: Int = 0) -> some View {
        modifier(CinematicReveal(index: index))
    }

    /// スクロールで画面の端に近づくと少し縮んで薄くなる
    func cinematicScroll() -> some View {
        scrollTransition(.interactive, axis: .vertical) { content, phase in
            content
                .scaleEffect(phase.isIdentity ? 1 : 0.95)
                .opacity(phase.isIdentity ? 1 : 0.6)
                .blur(radius: phase.isIdentity ? 0 : 2)
        }
    }
}

// MARK: - リキッドグラス（iOS 26）。それより前はすりガラスで代用

extension View {
    @ViewBuilder
    func liquidGlass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = true) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(Self.makeGlass(tint: tint, interactive: interactive), in: shape)
        } else {
            self
                .background {
                    if let tint { shape.fill(tint) } else { shape.fill(.ultraThinMaterial) }
                }
                .overlay(shape.stroke(Color.white.opacity(0.15), lineWidth: 0.5))
        }
    }

    @available(iOS 26.0, *)
    private static func makeGlass(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

struct GlassPrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.ink
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(Theme.paper)
            .frame(maxWidth: .infinity, minHeight: 54)
            .liquidGlass(in: Capsule(), tint: tint.opacity(isEnabled ? 0.94 : 0.3))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

struct GlassCircleButtonStyle: ButtonStyle {
    var size: CGFloat = 40

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Theme.ink)
            .frame(width: size, height: size)
            .liquidGlass(in: Circle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

struct GlassCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .liquidGlass(in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

/// 押すと少し沈むカード
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

// MARK: - カード

struct CardBackground: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line, lineWidth: 0.75))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardBackground(padding: padding)) }
}

// MARK: - 外観

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "端末に合わせる"
        case .light: return "ライト"
        case .dark: return "ダーク"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct GlassSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 48)
            .liquidGlass(in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
