import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 共享的应用状态 ViewModel
@MainActor
final class SweepViewModel: ObservableObject {

    // MARK: - 状态

    @Published var target: AppTarget?
    @Published var scanResult: ScanResult?
    @Published var isScanning = false
    @Published var isDeleting = false
    @Published var checkedIDs: Set<UUID> = []
    @Published var deletionRecords: [DeletionRecord] = []
    @Published var showResultPanel = false
    @Published var toastMessage: String?
    @Published var deletionProgress: (done: Int, total: Int)?
    @Published var scanStep: String?
    @Published var hasFullDiskAccess = FullDiskAccess.isGranted

    // MARK: - 派生

    var checkedItems: [ScannedItem] {
        guard let result = scanResult else { return [] }
        return result.items.filter { checkedIDs.contains($0.id) }
    }

    var checkedTotalSize: Int64 { checkedItems.map(\.size).reduce(0, +) }

    var successCount: Int { deletionRecords.filter(\.isSuccess).count }
    var failedCount: Int { deletionRecords.filter { if case .failed = $0.outcome { return true }; return false }.count }
    var skippedCount: Int { deletionRecords.filter { if case .skipped = $0.outcome { return true }; return false }.count }

    // MARK: - 操作

    func handleDroppedFile(url: URL) {
        guard !isScanning && !isDeleting else { return }

        guard let appTarget = AppTarget.parse(from: url) else {
            showToast("请拖入有效的 .app 应用")
            return
        }

        if appTarget.isSystemApp {
            let alert = NSAlert()
            alert.messageText = "这是 Apple 系统 App"
            alert.informativeText = "清理系统 App 的残留可能破坏系统功能。是否继续扫描？"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "继续扫描")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        target = appTarget
        checkedIDs.removeAll()
        deletionRecords.removeAll()
        showResultPanel = false

        startScan()
    }

    func handleOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "选择要清理的 App"
        if panel.runModal() == .OK, let url = panel.url {
            handleDroppedFile(url: url)
        }
    }

    func startScan() {
        guard let target = target else { return }
        isScanning = true
        scanResult = nil
        scanStep = "正在准备扫描…"

        let engine = ScanEngine { [weak self] step in
            Task { @MainActor in
                self?.scanStep = step
            }
        }

        Task { [weak self] in
            guard let self else { return }
            let result = await engine.scan(target: target)
            self.scanResult = result
            self.checkedIDs = Set(result.items.filter { $0.category.defaultChecked }.map(\.id))
            self.isScanning = false
            self.scanStep = nil
            if result.items.isEmpty {
                self.showToast("没找到残留文件，已经很干净了")
            }
        }
    }

    // MARK: - 权限体检

    func refreshPermissionStatus() {
        hasFullDiskAccess = FullDiskAccess.isGranted
        if hasFullDiskAccess {
            showToast("权限已生效")
        }
    }

    func openFullDiskAccessSettings() {
        FullDiskAccess.openSettings()
    }

    func toggleCheck(_ item: ScannedItem) {
        if checkedIDs.contains(item.id) {
            checkedIDs.remove(item.id)
        } else {
            checkedIDs.insert(item.id)
        }
    }

    func selectAllRedOrange() {
        guard let result = scanResult else { return }
        checkedIDs = Set(result.items.filter { $0.category.defaultChecked }.map(\.id))
    }

    func deselectAll() {
        checkedIDs.removeAll()
    }

    func startDeletion() {
        guard !isDeleting else { return }
        let toDelete = checkedItems
        guard !toDelete.isEmpty else {
            showToast("请先勾选要清理的文件")
            return
        }

        isDeleting = true
        deletionRecords.removeAll()
        deletionProgress = (0, toDelete.count)

        let engine = DeletionEngine()
        engine.onRecord = { [weak self] record in
            self?.deletionRecords.append(record)
        }
        engine.onProgress = { [weak self] done, total in
            self?.deletionProgress = (done, total)
        }

        Task { [weak self] in
            guard let self else { return }
            let records = await engine.delete(items: toDelete)
            self.deletionRecords = records.sorted { $0.timestamp < $1.timestamp }
            self.deletionProgress = nil
            self.isDeleting = false
            self.showResultPanel = true
        }
    }

    // MARK: - 辅助

    func revealInFinder(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            openTrash()
        }
    }

    func openTrash() {
        NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.Trash"))
    }

    func clearAll() {
        target = nil
        scanResult = nil
        checkedIDs.removeAll()
        deletionRecords.removeAll()
        showResultPanel = false
    }

    private func showToast(_ msg: String) {
        toastMessage = msg
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if self?.toastMessage == msg { self?.toastMessage = nil }
        }
    }
}
