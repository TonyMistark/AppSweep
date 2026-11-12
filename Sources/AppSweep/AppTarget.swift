import Foundation
import AppKit
import CoreGraphics

/// 被拖入的目标 App bundle
struct AppTarget: Identifiable, Hashable {
    let id: UUID = UUID()
    let bundleURL: URL
    let bundleID: String
    let displayName: String
    let version: String
    let executableName: String
    let applicationGroups: [String]
    let isSystemApp: Bool
    let icon: NSImage?

    /// 尝试从一个 .app bundle URL 构造 AppTarget
    static func parse(from url: URL) -> AppTarget? {
        guard url.pathExtension == "app" else { return nil }
        guard let bundle = Bundle(url: url) else { return nil }

        let bundleID = bundle.bundleIdentifier ?? ""
        guard !bundleID.isEmpty else { return nil }

        let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent

        let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
            ?? "?"

        let executableName = (bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String)
            ?? bundleID.components(separatedBy: ".").last
            ?? ""

        let groups = bundle.object(forInfoDictionaryKey: "com.apple.security.application-groups") as? [String] ?? []

        let isSystemApp = url.path.hasPrefix("/System/Applications") || url.path.hasPrefix("/Applications/Utilities")

        let icon = NSWorkspace.shared.icon(forFile: url.path)

        return AppTarget(
            bundleURL: url,
            bundleID: bundleID,
            displayName: displayName,
            version: version,
            executableName: executableName,
            applicationGroups: groups,
            isSystemApp: isSystemApp,
            icon: icon
        )
    }

    /// App 是否正在运行
    var isRunning: Bool {
        let workspace = NSWorkspace.shared
        return workspace.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }
}
