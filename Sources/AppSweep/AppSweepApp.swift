import SwiftUI
import AppKit

@main
struct AppSweepApp: App {
    @StateObject private var viewModel = SweepViewModel()

    var body: some Scene {
        WindowGroup("AppSweep") {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 720, minHeight: 480)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .appSettings) {}
            CommandGroup(after: .appInfo) {
                Button("关于 AppSweep") {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
            }
        }
    }
}
