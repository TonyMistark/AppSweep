import Foundation
import AppKit

/// 扫描引擎：给定 AppTarget，枚举所有关联文件
final class ScanEngine {

    /// 当前扫描阶段回调（在后台线程触发）
    private let onStep: @Sendable (String) -> Void

    init(onStep: @escaping @Sendable (String) -> Void = { _ in }) {
        self.onStep = onStep
    }

    /// 扫描目标 App，返回 ScanResult
    func scan(target: AppTarget) async -> ScanResult {
        let startedAt = Date()
        var items: [ScannedItem] = []

        onStep("正在扫描用户库目录…")
        items.append(contentsOf: await withTaskGroup(of: [ScannedItem].self) { group in
            for rule in standardPathRules(for: target) {
                group.addTask { [weak self] in
                    guard let self else { return [] }
                    return self.enumeratePaths(matching: rule)
                }
            }
            var collected: [ScannedItem] = []
            for await batch in group {
                collected.append(contentsOf: batch)
            }
            return collected
        })

        onStep("正在查询 Spotlight 索引…")
        let spotlightItems = spotLightScan(bundleID: target.bundleID, timeout: 2.0)
        items.append(contentsOf: spotlightItems)

        onStep("正在检查系统级路径…")
        let systemItems = enumerateSystemPaths(for: target)
        items.append(contentsOf: systemItems)

        onStep("正在整理扫描结果…")
        items = deduplicate(items)
            .filter { $0.url.path != target.bundleURL.path }

        return ScanResult(
            target: target,
            items: items,
            startedAt: startedAt,
            finishedAt: Date()
        )
    }

    // MARK: - 标准路径规则生成

    private struct PathRule {
        let baseDir: String
        let candidates: [String]
        let category: ItemCategory
        let matchRule: MatchRule
        let recursive: Bool
    }

    private func standardPathRules(for target: AppTarget) -> [PathRule] {
        let home = NSHomeDirectory()
        let bundleID = target.bundleID
        let name = target.displayName
        let exec = target.executableName

        var rules: [PathRule] = []

        // Application Support
        for cand in [bundleID, name, exec] {
            rules.append(PathRule(
                baseDir: "\(home)/Library/Application Support",
                candidates: [cand], category: .applicationSupport,
                matchRule: .bundleIDExactPath, recursive: false))
        }

        // Preferences
        rules.append(PathRule(
            baseDir: "\(home)/Library/Preferences",
            candidates: ["\(bundleID).plist"],
            category: .preferences, matchRule: .bundleIDExactPath, recursive: true))
        rules.append(PathRule(
            baseDir: "\(home)/Library/Preferences/ByHost",
            candidates: ["\(bundleID).*.plist"],
            category: .preferences, matchRule: .bundleIDPrefix, recursive: false))

        // Caches
        for cand in [bundleID, name, exec] {
            rules.append(PathRule(
                baseDir: "\(home)/Library/Caches",
                candidates: [cand, "\(cand)*"], category: .caches,
                matchRule: .bundleIDExactPath, recursive: false))
        }

        // Containers
        rules.append(PathRule(
            baseDir: "\(home)/Library/Containers",
            candidates: [bundleID, "\(bundleID)*"],
            category: .containers, matchRule: .bundleIDPrefix, recursive: false))

        // Group Containers
        for group in target.applicationGroups {
            rules.append(PathRule(
                baseDir: "\(home)/Library/Group Containers",
                candidates: [group],
                category: .groupContainers, matchRule: .bundleIDExactPath, recursive: false))
        }

        // Logs
        for cand in [name, exec] {
            rules.append(PathRule(
                baseDir: "\(home)/Library/Logs",
                candidates: [cand],
                category: .logs, matchRule: .displayNameFuzzy, recursive: false))
        }

        // Saved Application State
        rules.append(PathRule(
            baseDir: "\(home)/Library/Saved Application State",
            candidates: ["\(bundleID).savedState"],
            category: .savedState, matchRule: .bundleIDExactPath, recursive: false))

        // WebKit
        for cand in [bundleID, name] {
            rules.append(PathRule(
                baseDir: "\(home)/Library/WebKit",
                candidates: [cand],
                category: .webkit, matchRule: .bundleIDExactPath, recursive: false))
        }

        // Application Scripts
        rules.append(PathRule(
            baseDir: "\(home)/Library/Application Scripts",
            candidates: [bundleID, "\(bundleID)*"],
            category: .applicationScripts, matchRule: .bundleIDPrefix, recursive: false))

        // LaunchAgents
        rules.append(PathRule(
            baseDir: "\(home)/Library/LaunchAgents",
            candidates: ["*\(bundleID)*", "*\(name)*"],
            category: .launchAgents, matchRule: .displayNameFuzzy, recursive: false))

        return rules
    }

    private func enumerateSystemPaths(for target: AppTarget) -> [ScannedItem] {
        var result: [ScannedItem] = []
        let name = target.displayName

        let systemCandidates: [(String, String, ItemCategory)] = [
            ("/Library/Application Support", name, .systemLevel),
            ("/Library/Application Support", target.bundleID, .systemLevel),
            ("/Library/Preferences", "\(target.bundleID).plist", .preferences),
        ]

        for (base, cand, cat) in systemCandidates {
            let url = URL(fileURLWithPath: base).appendingPathComponent(cand)
            if FileManager.default.fileExists(atPath: url.path) {
                if let item = buildItem(url: url, category: cat,
                                        matchRule: .bundleIDExactPath,
                                        isSystemProtected: true) {
                    result.append(item)
                }
            }
        }
        return result
    }

    // MARK: - 路径枚举实现

    private func enumeratePaths(matching rule: PathRule) -> [ScannedItem] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: rule.baseDir) else { return [] }

        var result: [ScannedItem] = []
        let baseURL = URL(fileURLWithPath: rule.baseDir, isDirectory: true)

        guard let contents = try? fm.contentsOfDirectory(atPath: rule.baseDir) else {
            return []
        }

        for itemName in contents {
            let matched = rule.candidates.contains { pattern in
                wildcardMatch(itemName, pattern)
            }
            if !matched { continue }

            let url = baseURL.appendingPathComponent(itemName)
            guard fm.fileExists(atPath: url.path) else { continue }

            if let item = buildItem(url: url, category: rule.category,
                                    matchRule: rule.matchRule,
                                    isSystemProtected: false) {
                result.append(item)
            }
        }

        return result
    }

    /// 简单的通配符匹配（* ?）
    private func wildcardMatch(_ text: String, _ pattern: String) -> Bool {
        // 用 NSString 的 fnmatch 思路：把 * ? 翻译成正则
        var regexPattern = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: #"\\\*"#, with: ".*", options: .regularExpression)
            .replacingOccurrences(of: #"\\\?"#, with: ".", options: .regularExpression)
        // 上面 escapedPattern 会把 * 变成 \*，把 ? 变成 \?，我们再反替换回来
        regexPattern = regexPattern
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".")

        if let regex = try? NSRegularExpression(pattern: "^" + regexPattern + "$") {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.firstMatch(in: text, range: range) != nil
        }
        return text == pattern
    }

    // MARK: - Spotlight 扫描

    private func spotLightScan(bundleID: String, timeout: TimeInterval) -> [ScannedItem] {
        let semaphore = DispatchSemaphore(value: 0)
        var items: [ScannedItem] = []

        DispatchQueue.global(qos: .utility).async {
            let task = Process()
            task.launchPath = "/usr/bin/mdfind"
            task.arguments = ["kMDItemCFBundleIdentifier == '\(bundleID)'"]

            let pipe = Pipe()
            task.standardOutput = pipe

            let timeoutWork = DispatchWorkItem {
                if task.isRunning { task.terminate() }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

            defer { timeoutWork.cancel() }

            do {
                try task.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    let lines = output.split(separator: "\n")
                    for line in lines {
                        let path = String(line).trimmingCharacters(in: .whitespaces)
                        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { continue }
                        guard !path.hasPrefix("/System/") else { continue }
                        guard !path.hasSuffix(".app") else { continue }

                        let url = URL(fileURLWithPath: path)
                        let cat = self.classifySpotlightItem(url: url)
                        if let item = self.buildItem(url: url, category: cat,
                                                     matchRule: .spotlightExtAttr,
                                                     isSystemProtected: false) {
                            items.append(item)
                        }
                    }
                }
                task.waitUntilExit()
            } catch {
                // mdfind 不可用 → 返回空
            }

            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + timeout + 0.5)
        return items
    }

    private func classifySpotlightItem(url: URL) -> ItemCategory {
        let path = url.path
        if path.contains("/Library/Caches/") { return .caches }
        if path.contains("/Library/Application Support/") { return .applicationSupport }
        if path.contains("/Library/Preferences/") { return .preferences }
        if path.contains("/Library/Containers/") { return .containers }
        if path.contains("/Library/Group Containers/") { return .groupContainers }
        if path.contains("/Library/Logs/") { return .logs }
        if path.contains("/Library/WebKit/") { return .webkit }
        if path.contains("/Library/Saved Application State/") { return .savedState }
        if path.contains("/Library/Launch") { return .launchAgents }
        if path.contains("/Library/Application Scripts/") { return .applicationScripts }
        if path.hasPrefix("/Library/") { return .systemLevel }
        return .downloadData
    }

    // MARK: - ScannedItem 构建 + 去重

    private func buildItem(url: URL, category: ItemCategory, matchRule: MatchRule, isSystemProtected: Bool) -> ScannedItem? {
        let fm = FileManager.default
        let exists = fm.fileExists(atPath: url.path)
        guard exists else { return nil }

        let attrs = try? fm.attributesOfItem(atPath: url.path)
        let fileType = attrs?[.type] as? FileAttributeType
        let isSymlink = (fileType == .typeSymbolicLink)

        let size: Int64
        if fileType == .typeDirectory {
            size = directorySize(url)
        } else if let s = attrs?[.size] as? NSNumber {
            size = s.int64Value
        } else {
            size = 0
        }

        let isAppBundle = url.pathExtension == "app"

        return ScannedItem(
            url: url,
            category: category,
            size: size,
            matchedBy: matchRule,
            isSymlink: isSymlink,
            isSystemProtected: isSystemProtected,
            isAppBundle: isAppBundle
        )
    }

    private func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        var total: Int64 = 0
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else {
            if let attrs = try? fm.attributesOfItem(atPath: url.path),
               let s = attrs[.size] as? NSNumber {
                return s.int64Value
            }
            return 0
        }
        for case let itemURL as URL in enumerator {
            if let resources = try? itemURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
               resources.isRegularFile == true,
               let size = resources.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    private func deduplicate(_ items: [ScannedItem]) -> [ScannedItem] {
        var seen = Set<String>()
        var result: [ScannedItem] = []
        for item in items {
            let key = item.url.standardizedFileURL.path
            if !seen.contains(key) {
                seen.insert(key)
                result.append(item)
            }
        }
        return result
    }
}
