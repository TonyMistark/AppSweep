import Foundation
import AppKit

/// 格式化文件大小为人类可读字符串
func humanSize(_ bytes: Int64) -> String {
    guard bytes > 0 else { return "0 B" }
    let kb = 1024.0
    let mb = kb * 1024
    let gb = mb * 1024

    if Double(bytes) >= gb {
        return String(format: "%.2f GB", Double(bytes) / gb)
    } else if Double(bytes) >= mb {
        return String(format: "%.1f MB", Double(bytes) / mb)
    } else if Double(bytes) >= kb {
        return String(format: "%.1f KB", Double(bytes) / kb)
    } else {
        return "\(bytes) B"
    }
}

extension ItemCategory {
    /// 颜色标签对应的语义颜色（在 NSColor 中使用）
    var semanticNSColor: NSColor {
        switch colorTag {
        case 0: return .systemRed
        case 1: return .systemOrange
        case 2: return .systemYellow
        case 3: return .systemBlue
        case 4: return .systemPurple
        default: return .systemGray
        }
    }
}
