import Foundation
import AppKit

/// 完全磁盘访问权限检测与引导
enum FullDiskAccess {

    /// TCC.db 只有在拥有「完全磁盘访问权限」时才能被读取，用它作为判断依据
    static var isGranted: Bool {
        let path = NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db"
        guard FileManager.default.fileExists(atPath: path) else {
            // 文件不存在时无法判定，按已授权处理，避免无谓打扰
            return true
        }
        do {
            let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
            try? handle.close()
            return true
        } catch {
            return false
        }
    }

    /// 打开「隐私与安全性 → 完全磁盘访问权限」面板
    static func openSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ]
        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
