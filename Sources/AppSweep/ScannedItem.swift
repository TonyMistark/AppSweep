import Foundation

/// 扫描结果分类
enum ItemCategory: String, CaseIterable, Identifiable, Hashable {
    case applicationSupport
    case preferences
    case caches
    case containers
    case groupContainers
    case logs
    case savedState
    case webkit
    case launchAgents
    case applicationScripts
    case downloadData
    case systemLevel
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .applicationSupport: return "Application Support"
        case .preferences:       return "偏好设置"
        case .caches:            return "缓存"
        case .containers:        return "沙盒容器"
        case .groupContainers:   return "共享容器"
        case .logs:              return "日志"
        case .savedState:        return "Saved State"
        case .webkit:            return "WebKit 数据"
        case .launchAgents:      return "登录项/守护进程"
        case .applicationScripts: return "Application Scripts"
        case .downloadData:      return "关联数据"
        case .systemLevel:       return "系统级文件"
        case .other:             return "其他"
        }
    }

    /// 默认是否勾选
    var defaultChecked: Bool {
        switch self {
        case .applicationSupport, .preferences, .caches, .containers,
             .groupContainers, .webkit, .launchAgents, .applicationScripts, .systemLevel:
            return true
        case .logs, .savedState, .downloadData, .other:
            return false
        }
    }

    /// UI 颜色标记语义（0-红色, 1-橙色, 2-黄色, 3-蓝色, 4-紫色, 5-灰色）
    var colorTag: Int {
        switch self {
        case .applicationSupport, .preferences, .containers, .groupContainers, .launchAgents:
            return 0
        case .caches, .webkit, .applicationScripts:
            return 1
        case .logs, .savedState:
            return 2
        case .downloadData:
            return 3
        case .systemLevel:
            return 4
        case .other:
            return 5
        }
    }
}

/// 匹配规则来源
enum MatchRule: String, CaseIterable {
    case bundleIDExactPath    // 路径直接包含 bundle ID
    case bundleIDPrefix       // 目录名以 bundle ID 开头（沙盒变体）
    case spotlightExtAttr     // Spotlight 扩展属性 kMDItemCFBundleIdentifier
    case displayNameFuzzy     // 与显示名模糊匹配
    case executableNameExact  // 匹配可执行文件名
}

/// 一个待清理文件或目录
struct ScannedItem: Identifiable, Hashable {
    let id: UUID = UUID()
    let url: URL
    let category: ItemCategory
    let size: Int64
    let matchedBy: MatchRule
    let isSymlink: Bool
    let isSystemProtected: Bool
    let isAppBundle: Bool

    var exists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}

/// 扫描结果集合
struct ScanResult: Hashable {
    let target: AppTarget
    var items: [ScannedItem]
    let startedAt: Date
    var finishedAt: Date?

    var hasErrors: Bool { false }
    var totalSize: Int64 { items.map(\.size).reduce(0, +) }
}

/// 删除执行结果
enum DeletionOutcome: Hashable {
    case movedToTrash
    case skipped(SkipReason)
    case failed(String)
}

enum SkipReason: String, Hashable {
    case userRejectedPermission = "用户拒绝了权限请求"
    case fileNotFound = "文件不存在"
    case isAppBundle = "App 本体（自动跳过）"
    case systemProtected = "系统保护"
    case excludedByRule = "已在排除规则中"
    case locked = "文件被锁定"
}

struct DeletionRecord: Identifiable, Hashable {
    let id: UUID = UUID()
    let item: ScannedItem
    let outcome: DeletionOutcome
    let timestamp: Date

    var isSuccess: Bool {
        if case .movedToTrash = outcome { return true }
        return false
    }
}
