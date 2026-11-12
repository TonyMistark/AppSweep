import Foundation
import AppKit

/// 删除执行引擎
enum DeletionEngine {

    /// 执行删除
    static func delete(items: [ScannedItem]) async -> [DeletionRecord] {
        var records: [DeletionRecord] = []

        let priorityOrder: [ItemCategory] = [
            .caches, .preferences, .applicationSupport,
            .containers, .groupContainers,
            .webkit, .applicationScripts,
            .savedState, .logs,
            .systemLevel,
            .downloadData, .other
        ]
        let sorted = items.sorted {
            let a = priorityOrder.firstIndex(of: $0.category) ?? 99
            let b = priorityOrder.firstIndex(of: $1.category) ?? 99
            return a < b
        }

        for item in sorted {
            let record = deleteOne(item)
            records.append(record)
        }

        return records
    }

    private static func deleteOne(_ item: ScannedItem) -> DeletionRecord {
        let now = Date()
        let fm = FileManager.default

        if item.isAppBundle {
            return DeletionRecord(item: item, outcome: .skipped(.isAppBundle), timestamp: now)
        }

        if !fm.fileExists(atPath: item.url.path) {
            return DeletionRecord(item: item, outcome: .skipped(.fileNotFound), timestamp: now)
        }

        do {
            try fm.trashItem(at: item.url, resultingItemURL: nil)
            return DeletionRecord(item: item, outcome: .movedToTrash, timestamp: now)
        } catch {
            let workspace = NSWorkspace.shared
            let urlset = Set([item.url])
            if workspace.recycle(urls: urlset) {
                return DeletionRecord(item: item, outcome: .movedToTrash, timestamp: now)
            }
            return DeletionRecord(item: item, outcome: .failed(error.localizedDescription), timestamp: now)
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
