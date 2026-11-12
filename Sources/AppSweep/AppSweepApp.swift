import SwiftUI
import AppKit

// MARK: - 应用级服务

/// 应用生命周期里只有一份的东西：更新检查、更新安装、崩溃账本。
/// 别塞进某个窗口——设置页和崩溃面板都要从这取。
@MainActor
final class AppServices: ObservableObject {
    let updates = UpdateChecker()
    let installer = UpdateInstaller(steps: UpdateInstaller.productionSteps())
    let crashes = CrashStore()

    init() {
        // 顺序不能反：先收上次的尸（读轨迹文件），再装处理器——
        // 装处理器时会清空轨迹本，那是留给这一次用的。
        crashes.harvest()
        CrashBreadcrumbs.install(directory: crashes.directory)
        CrashCatcher.install(directory: crashes.directory)
        CrashBreadcrumbs.note("launch \(CrashEnvironment.appVersion)")
    }
}

@main
struct AppSweepApp: App {
    @StateObject private var services: AppServices
    @StateObject private var crashPrompt: CrashPrompt
    @StateObject private var viewModel = SweepViewModel()

    init() {
        let services = AppServices()
        _services = StateObject(wrappedValue: services)
        _crashPrompt = StateObject(wrappedValue: CrashPrompt(store: services.crashes))
    }

    /// 打开设置窗口。`\.openSettings` 环境要 macOS 14，这里统一走
    /// Settings scene 响应的动作，13 / 14 都认。
    private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    var body: some Scene {
        WindowGroup("AppSweep") {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 720, minHeight: 480)
                .crashPrompt(crashPrompt)
                .task { crashPrompt.offerIfNeeded() }
                .task { await services.updates.checkIfDue() }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .appSettings) {}
            CommandGroup(after: .appInfo) {
                Button(t("About AppSweep")) { AboutPanel.show() }
                Button(t("Settings…")) { openSettingsWindow() }
                    .keyboardShortcut(",")
            }
        }

        Settings {
            AppSettingsView()
                .environmentObject(services.updates)
                .environmentObject(services.installer)
                .environmentObject(services.crashes)
        }
    }
}
