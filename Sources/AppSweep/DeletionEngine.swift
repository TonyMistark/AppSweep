import Foundation
import AppKit

/// 用户对单个敏感路径的授权决定
enum PermissionDecision {
    case allowOnce
    case allowAll
    case skip
}

/// 删除执行引擎：逐项校验权限、必要时弹出确认、统一移入废纸篓
@MainActor
final class DeletionEngine {

    /// 删除进度回调（已完成, 总数）
    var onProgress: ((Int, Int) -> Void)?
    /// 单项完成回调
    var onRecord: ((DeletionRecord) -> Void)?

    /// 本次清理中用户是否选择了"全部允许"
    private var allowAll = false

    /// 用户主目录，用于判断是否为系统级路径
    private let homePath = NSHomeDirectory()

    private static let priorityOrder: [ItemCategory] = [
        .caches, .preferences, .applicationSupport,
        .containers, .groupContainers,
        .webkit, .applicationScripts,
        .savedState, .logs,
        .systemLevel,
        .downloadData, .other
    ]

    func delete(items: [ScannedItem]) async -> [DeletionRecord] {
        allowAll = false

        let sorted = items.sorted {
            let a = Self.priorityOrder.firstIndex(of: $0.category) ?? 99
            let b = Self.priorityOrder.firstIndex(of: $1.category) ?? 99
            return a < b
        }

        var records: [DeletionRecord] = []
        let total = sorted.count

        for (index, item) in sorted.enumerated() {
            let record = deleteOne(item)
            records.append(record)
            onRecord?(record)
            onProgress?(index + 1, total)
            // 让出主线程，保证进度能刷新
            await Task.yield()
        }

        return records
    }

    // MARK: - 单项删除

    private func deleteOne(_ item: ScannedItem) -> DeletionRecord {
        let now = Date()
        let fm = FileManager.default

        // App 本体永远不删（人身安全护栏）
        if item.isAppBundle {
            return DeletionRecord(item: item, outcome: .skipped(.isAppBundle), timestamp: now)
        }

        if !fm.fileExists(atPath: item.url.path) {
            return DeletionRecord(item: item, outcome: .skipped(.fileNotFound), timestamp: now)
        }

        // 敏感路径需要用户授权
        if needsPermissionPrompt(item) && !allowAll {
            switch askPermission(for: item) {
            case .skip:
                return DeletionRecord(item: item, outcome: .skipped(.userRejectedPermission), timestamp: now)
            case .allowAll:
                allowAll = true
            case .allowOnce:
                break
            }
        }

        // 父目录不可写：直接给可操作的提示，而不是让系统抛晦涩错误
        let parent = item.url.deletingLastPathComponent().path
        if !fm.isWritableFile(atPath: parent) {
            return DeletionRecord(
                item: item,
                outcome: .failed("所在目录不可写，请在「系统设置 → 隐私与安全性 → 完全磁盘访问权限」中授权 AppSweep 后重试"),
                timestamp: now
            )
        }

        do {
            try fm.trashItem(at: item.url, resultingItemURL: nil)
            return DeletionRecord(item: item, outcome: .movedToTrash, timestamp: now)
        } catch {
            // 二次尝试：部分目录对 trashItem 有限制
            if NSWorkspace.shared.recycle(urls: Set([item.url])) {
                return DeletionRecord(item: item, outcome: .movedToTrash, timestamp: now)
            }
            return DeletionRecord(
                item: item,
                outcome: .failed(friendlyMessage(for: error)),
                timestamp: now
            )
        }
    }

    // MARK: - 权限判定与弹窗

    private func needsPermissionPrompt(_ item: ScannedItem) -> Bool {
        if item.isSystemProtected { return true }
        // 主目录之外视为需要确认（/Library 等系统级位置）
        return !item.url.path.hasPrefix(homePath)
    }

    private func askPermission(for item: ScannedItem) -> PermissionDecision {
        let alert = NSAlert()
        alert.messageText = "需要你的授权才能删除"
        alert.informativeText = """
        位置：\(item.url.path)
        类型：\(item.category.displayName) · \(humanSize(item.size))

        这个位置在用户目录之外，删除前需要你确认。拒绝不会影响其他文件的清理。
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "允许删除")
        alert.addButton(withTitle: "跳过这一项")
        alert.addButton(withTitle: "本次全部允许")

        switch alert.runModal() {
        case .alertFirstButtonReturn:  return .allowOnce
        case .alertThirdButtonReturn:  return .allowAll
        default:                       return .skip
        }
    }

    private func friendlyMessage(for error: Error) -> String {
        let nsError = error as NSError
        switch nsError.code {
        case NSFileWriteNoPermissionError, NSFileReadNoPermissionError:
            return "无权限访问，可能需要在「完全磁盘访问权限」中授权 AppSweep"
        default:
            return nsError.localizedDescription
        }
    }
}

extension NSWorkspace {
    /// 回收一组 URL 到废纸篓
    @discardableResult
    func recycle(urls: Set<URL>) -> Bool {
        let fileManager = FileManager.default
        var success = true
        for url in urls {
            do {
                try fileManager.trashItem(at: url, resultingItemURL: nil)
            } catch {
                success = false
            }
        }
        return success
    }
}
