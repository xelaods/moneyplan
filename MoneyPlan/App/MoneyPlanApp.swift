import SwiftUI

@main
struct MoneyPlanApp: App {
    @StateObject private var store = Store.shared
    @StateObject private var router = AppRouter.shared

    var body: some Scene {
        WindowGroup {
            AppRoot()
                .environmentObject(store)
                .environmentObject(router)
        }
    }
}

struct AppRoot: View {
    @EnvironmentObject var store: Store
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    @State private var launching = !Store.isDemo
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Group {
                if ProcessInfo.processInfo.arguments.contains("-gallery") {
                    WidgetGallery()
                } else {
                    MainTabView()
                }
            }
            .scaleEffect(launching ? 0.92 : 1)
            .blur(radius: launching ? 18 : 0)
            .allowsHitTesting(!launching)

            if launching {
                LaunchView {
                    withAnimation(Motion.cinematic) { launching = false }
                }
                .zIndex(1)
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.reload() }
        }
    }
}

/// 下のタブ：ホーム・明細・分析・設定
struct MainTabView: View {
    enum Tab: Hashable { case home, ledger, analysis, settings }

    @EnvironmentObject var store: Store
    @EnvironmentObject var router: AppRouter
    @State private var tab: Tab = MainTabView.initialTab
    @State private var editing: EntryTarget?

    private static var initialTab: Tab {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-tab"), i + 1 < args.count else { return .home }
        switch args[i + 1] {
        case "ledger": return .ledger
        case "analysis": return .analysis
        case "settings": return .settings
        default: return .home
        }
    }

    var body: some View {
        TabView(selection: $tab) {
            HomeView(edit: { editing = $0 }, open: { t in withAnimation(Motion.cinematicFast) { tab = t } })
                .tabItem { Label("ホーム", systemImage: "yensign.circle") }
                .tag(Tab.home)
            LedgerView(edit: { editing = $0 })
                .tabItem { Label("明細", systemImage: "list.bullet.rectangle") }
                .tag(Tab.ledger)
            AnalysisView()
                .tabItem { Label("分析", systemImage: "chart.pie") }
                .tag(Tab.analysis)
            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .sheet(item: $editing) { target in
            EntrySheet(target: target)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
        }
        .overlay(alignment: .bottom) { UndoBanner() }
        // ウィジェットやショートカットから開いたとき（moneyplan://add・moneyplan://ledger など）
        .onOpenURL { url in
            guard url.scheme == "moneyplan" else { return }
            withAnimation(Motion.cinematicFast) {
                switch url.host {
                case "add": editing = .new(.expense)
                case "income": editing = .new(.income)
                case "ledger": tab = .ledger
                case "analysis": tab = .analysis
                case "settings": tab = .settings
                default: tab = .home
                }
            }
        }
        .onChange(of: router.pendingAdd) { _, pending in
            if pending { editing = .new(.expense); router.pendingAdd = false }
        }
        .onAppear {
            if router.pendingAdd { editing = .new(.expense); router.pendingAdd = false }
            if ProcessInfo.processInfo.arguments.contains("-add") { editing = .new(.expense) }
        }
    }
}

/// 入力シートで開くもの
enum EntryTarget: Identifiable, Hashable {
    case new(TxnKind)
    case edit(Txn)

    var id: String {
        switch self {
        case .new(let k): return "new-\(k.rawValue)"
        case .edit(let t): return t.id.uuidString
        }
    }
}

/// 消したときに出る「元に戻す」
struct UndoBanner: View {
    @EnvironmentObject var store: Store

    var body: some View {
        Group {
            if !store.lastDeleted.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "trash")
                        .foregroundStyle(Theme.muted)
                    Text(store.lastDeleted.count == 1 ? "1件を削除しました" : "\(store.lastDeleted.count)件を削除しました")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Button("元に戻す") {
                        withAnimation(Motion.snappy) { store.undoDelete() }
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 18)
                .frame(height: 50)
                .liquidGlass(in: Capsule())
                .padding(.horizontal, 20)
                .padding(.bottom, 64)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: store.lastDeleted) {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    withAnimation(Motion.snappy) { store.clearUndo() }
                }
            }
        }
        .animation(Motion.snappy, value: store.lastDeleted)
    }
}

/// 起動時：レシートが下から送り出されて、合計欄にピントが合う
struct LaunchView: View {
    let onFinish: () -> Void
    @State private var phase = 0

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            VStack(spacing: 20) {
                ZStack(alignment: .top) {
                    ReceiptShape()
                        .fill(Theme.card)
                        .frame(width: 96, height: 124)
                        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
                    VStack(spacing: 7) {
                        ForEach(0..<3, id: \.self) { i in
                            HStack {
                                Capsule().fill(Theme.faint).frame(width: [34, 26, 40][i], height: 4)
                                Spacer()
                                Capsule().fill(Theme.faint).frame(width: [16, 20, 12][i], height: 4)
                            }
                        }
                        Rectangle().fill(Theme.line).frame(height: 1).padding(.vertical, 3)
                        HStack(alignment: .firstTextBaseline) {
                            Text("¥")
                                .font(Theme.number(30, weight: .black))
                                .foregroundStyle(Theme.accent)
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .frame(width: 96)
                }
                .offset(y: phase >= 1 ? 0 : 60)
                .scaleEffect(phase >= 1 ? 1 : 0.86)
                .blur(radius: phase >= 1 ? 0 : 12)
                .opacity(phase >= 1 ? 1 : 0)
                .clipped()

                Text("MoneyPlan")
                    .font(.system(size: 30, weight: .heavy).width(.condensed))
                    .foregroundStyle(Theme.ink)
                    .tracking(phase >= 2 ? 0.5 : 6)
                    .blur(radius: phase >= 2 ? 0 : 8)
                    .opacity(phase >= 2 ? 1 : 0)
            }
            .scaleEffect(phase >= 3 ? 1.06 : 1)
            .blur(radius: phase >= 3 ? 14 : 0)
            .opacity(phase >= 3 ? 0 : 1)
        }
        .opacity(phase >= 3 ? 0 : 1)
        .task {
            withAnimation(Motion.cinematic) { phase = 1 }
            try? await Task.sleep(nanoseconds: 250_000_000)
            withAnimation(Motion.cinematic) { phase = 2 }
            try? await Task.sleep(nanoseconds: 700_000_000)
            withAnimation(Motion.cinematicFast) { phase = 3 }
            try? await Task.sleep(nanoseconds: 250_000_000)
            onFinish()
        }
    }
}

/// 下の端がギザギザのレシート
struct ReceiptShape: Shape {
    var teeth = 8

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r: CGFloat = 10
        let tooth = rect.width / CGFloat(teeth)
        let depth: CGFloat = 5
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        for i in 0..<teeth {
            let x0 = rect.maxX - CGFloat(i) * tooth
            p.addLine(to: CGPoint(x: x0 - tooth / 2, y: rect.maxY - depth))
            p.addLine(to: CGPoint(x: x0 - tooth, y: rect.maxY))
        }
        p.closeSubpath()
        return p
    }
}
