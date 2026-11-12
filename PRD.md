# AppSweep PRD — macOS 应用清理工具

> 版本 v1.0 · 最后更新 2026-11-11

---

## 1. 背景与目标

### 1.1 观察到的问题

用户在 macOS 上尝试新 App 后，简单将 `.app` 拖到废纸篓并不能移除该 App 产生的数据文件。这些残留包括：

- `~/Library/Application Support/` 下的整个数据目录
- `~/Library/Preferences/<bundleID>.plist` 偏好设置
- `~/Library/Caches/<bundleID>/` 或按 app 名命名的缓存目录
- `~/Library/Containers/<bundleID>/`（沙盒 App）
- `~/Library/Group Containers/<groupID>/`（共享容器）
- `~/Library/Logs/<appName>/` 日志
- `~/Library/Saved Application State/<bundleID>.savedState/`
- `~/Library/WebKit/<bundleID>/` WKWebView 数据
- `/Library/Application Support/<appName>/`（系统级）
- 可能在 `Downloads/`、`~/Movies/` 等目录下通过扩展属性关联的下载文件

长时间积累后，几个 GB 的残留文件并不罕见。macOS 系统和 Launchpad 都不提供"彻底卸载"入口。

### 1.2 受影响用户与时刻

- **用户画像**：喜欢尝试各种 App 的 Mac 用户（开发者、设计师、玩机党），以及需要释放磁盘空间的用户。
- **触发时刻**：安装/试用了一个 App 后觉得没用，或磁盘变红想清理。

### 1.3 产品决策 → 预期结果

| 产品决策 | 预期可观察结果 |
|---|---|
| 用拖拽作为唯一主入口（与用户"拖到废纸篓"习惯一致） | 用户从 `/Applications` 拖一个 `.app` 到 AppSweep 即可触发扫描 |
| 多维度扫描：路径匹配 + Spotlight 扩展属性 + 模糊名匹配 | 扫描到的残留覆盖率 ≥ 95%；不依赖单一策略 |
| 列表化展示 + 逐项勾选 | 用户对每一个即将删除的文件有最终知情权 |
| 权限分级弹窗（可逐个拒绝） | 不会因为一次"全盘授权"把系统文件也删了；敏感路径单独提示 |
| 先移废纸篓再永久删除 | 可撤销；误删能在废纸篓恢复 |

---

## 2. 范围

### 2.1 入口条件

- 用户启动 AppSweep（菜单栏常驻或 Dock 图标，两者都支持）。
- 用户从 Finder、Launchpad 或其他路径把 `.app` bundle 拖到 AppSweep 窗口。

### 2.2 P0 — 最小完整旅程

1. 拖拽 `.app` → AppSweep 解析 bundle ID / app 名称
2. 后台扫描 ~5 类标准路径（见 §4.3 扫描规则）
3. UI 展示扫描结果列表，带：文件路径、所属类别、文件大小、勾选框
4. 用户逐项勾选（默认：数据/缓存/偏好勾选，日志和 SavedState 可按需）
5. 用户点"开始清理"→ 逐批弹出权限确认（仅涉及非用户主目录或 SIP 路径时才弹窗）
6. 选中项被移至废纸篓，结果面板列出成功/失败/跳过
7. 用户在废纸篓里确认后自行永久删除（或通过 AppSweep 的"清空废纸篓"按钮触发系统清理）

### 2.3 完成判定

- 扫描覆盖率 ≥ 90%（以 bundle ID 精确匹配和 Spotlight 扩展属性为准）
- 清理后，`~/Library/Application Support/<bundleID>/` 目录不存在且不报错
- 废纸篓中可见所有被删文件
- UI 展示哪些文件因权限被跳过、哪些已成功

### 2.4 P1 — 支持但非阻塞

- 菜单栏快速入口：右键 AppSweep 图标 → "扫描刚删除的 App"（监听废纸篓 .app 文件）
- 历史记录面板：已清理过哪些 App，释放了多少空间
- 扫描完成后计算"预计释放空间"
- 扫描规则可配置（Expert Mode）：添加自定义 bundle ID 或目录前缀
- 快速模式：一键"删除所有勾选"跳过逐项权限弹窗（仅针对 `~/Library` 下的文件）

### 2.5 明确排除

- **扩展卸载**：Safari 扩展、XPC Service、Login Item、Launch Daemon/Agent（P0 不做，单独 P2）
- **Spotify/Chrome 等下载文件**：用户自行管理的 App 文档目录（P0 不碰 Documents/Downloads/Movies 等用户数据目录）
- **磁盘级权限**：不尝试关闭 SIP，不走 `sudo`，不修改 `/usr` `/System`
- **卸载其他 App**：只清理被拖入的那个 App 的残留，不做全局"扫描所有已安装 App 的残留"
- **命令行版本**：本次只做 GUI

---

## 3. 产品模型

### 3.1 核心对象

| 对象 | 说明 | 关键字段 |
|---|---|---|
| **AppTarget** | 被拖入的目标 App bundle | `bundleURL: URL`、`bundleID: String`、`displayName: String`、`version: String`、`executableName: String`、`kMDItemFSInvisible: Bool`（是否系统隐藏 App） |
| **ScanResult** | 一次扫描的结果集合 | `target: AppTarget`、`items: [ScannedItem]`、`startedAt / finishedAt`、`hasErrors: Bool` |
| **ScannedItem** | 一个待清理文件或目录 | `url: URL`、`category: ItemCategory`、`size: Int64`、`exists: Bool`、`matchedBy: MatchRule`、`isSymlink: Bool`、`isSystemProtected: Bool` |
| **DeletionRecord** | 一次删除的执行结果 | `item: ScannedItem`、`action: .movedToTrash \| .skipped(reason) \| .failed(error)`、`timestamp` |

### 3.2 ItemCategory（扫描结果分类）

| Category | 匹配路径示例 | 默认勾选 | 颜色标记 |
|---|---|---|---|
| `.applicationSupport` | `~/Library/Application Support/<bundleID>`、`~/Library/Application Support/<name>` | ✅ | 红 |
| `.preferences` | `~/Library/Preferences/<bundleID>.plist`、`~/Library/Preferences/ByHost/<bundleID>.*.plist` | ✅ | 红 |
| `.caches` | `~/Library/Caches/<bundleID>`、`~/Library/Caches/<name>` | ✅ | 橙 |
| `.containers` | `~/Library/Containers/<bundleID>` | ✅ | 红 |
| `.groupContainers` | `~/Library/Group Containers/<groupID>` | ✅ | 红 |
| `.logs` | `~/Library/Logs/<name>`、`~/Library/Logs/DiagnosticReports/*<name>*` | ☐ | 黄 |
| `.savedState` | `~/Library/Saved Application State/<bundleID>.savedState` | ☐ | 黄 |
| `.webkit` | `~/Library/WebKit/<bundleID>`、`~/Library/WebKit/<name>` | ✅ | 橙 |
| `.launchAgents` | `~/Library/LaunchAgents/*<bundleID>*`、`/Library/LaunchAgents/*` | ✅ | 红 |
| `.applicationScripts` | `~/Library/Application Scripts/<bundleID>` | ✅ | 橙 |
| `.mailData` | `~/Library/Mail/*<bundleID>*`、`~/Library/Mail/V*/Mailboxes/*<name>*` | ☐ | 黄 |
| `.downloadsMatched` | 通过 `kMDItemCFBundleIdentifier` 扩展属性关联的任意文件 | ☐ | 蓝 |
| `.systemLevel` | `/Library/Application Support/<name>`、`/Library/Preferences/<bundleID>.plist` | ✅ | 紫 |
| `.other` | 以上不匹配但通过 Spotlight 扩展属性关联 | ☐ | 灰 |

> **颜色含义**：红=高置信度残留，应当删除；橙=较高置信度；黄=可能是用户主动保留的数据；蓝=关联文件；紫=系统级；灰=低置信度。

### 3.3 MatchRule（匹配规则来源）

| 规则 | 说明 | 置信度 |
|---|---|---|
| `bundleID.exactPath` | 路径中直接包含 bundle ID | 最高 |
| `bundleID.prefix` | 目录名以 bundle ID 开头（沙盒变体） | 高 |
| `spotlightExtAttr` | `mdls` 显示 `kMDItemCFBundleIdentifier` 匹配 | 高 |
| `displayName.fuzzy` | 目录/文件名与 App 显示名模糊匹配（≥ 70% 相似） | 中 |
| `executableName.exact` | 匹配 App 可执行文件名 | 中 |
| `reversedNSWorkspace` | 通过 `NSWorkspace.shared.urlsForApplications` 反向确认 | 辅助 |

---

## 4. 功能需求

### 4.1 模块一：拖拽接收

#### 4.1.1 Purpose
用户把 `.app` bundle 从 Finder 拖到 AppSweep 窗口后，AppSweep 解析 bundle 并触发扫描。

#### 4.1.2 Trigger
- **谁**：任意使用 AppSweep 的用户
- **条件**：AppSweep 窗口可见；拖入文件后缀为 `.app` 且能被 `Bundle(url:)` 成功初始化
- **额外入口**：菜单栏图标 → "扫描此 App..." → 弹出 NSOpenPanel；或快捷指令 URL scheme `appsweep://scan?path=/Applications/XXX.app`

#### 4.1.3 Processing Rules

| 规则 | 处理 |
|---|---|
| 拖入的不是 `.app` | 拒绝，抖动窗口，右下角 Toast "请拖入 .app 应用" |
| 拖入多个 App | 只处理第一个，Toast "仅支持同时扫描一个 App" |
| 拖入的 App 在系统目录（`/System/Applications`） | 弹出二次确认："这是 Apple 系统 App，清理可能破坏系统功能。是否继续？" |
| 拖入的 App bundle 损坏（Info.plist 解析失败） | Toast "无法读取此 App" |
| 重复扫描同一个 App | 直接替换上一次扫描结果并重新扫描 |

#### 4.1.4 Bundle 解析字段
必须从 `Info.plist` 读出以下字段，缺一即视为 bundle 无效：
- `CFBundleIdentifier`
- `CFBundleName`（或从 `CFBundleDisplayName` fallback）
- `CFBundleShortVersionString`
- `CFBundleExecutable`（可执行文件名）
- `com.apple.security.application-groups`（若存在 → 提取 group ID 列表）

---

### 4.2 模块二：扫描引擎

#### 4.2.1 Purpose
给定一个 AppTarget，扫描出所有关联文件，返回 ScannedItem 列表。

#### 4.2.2 Trigger
Bundle 解析成功后自动开始，同时 UI 显示扫描进度条。

#### 4.2.3 扫描流程（串行步骤，总预算 3-5 秒）

```
Step 1: 标准路径枚举        (并发，GCD 分组)
  ├── ~/Library/Application Support/<bundleID>
  ├── ~/Library/Application Support/<name>
  ├── ~/Library/Preferences/<bundleID>.plist + ByHost 变体
  ├── ~/Library/Caches/<bundleID> + <name>
  ├── ~/Library/Containers/<bundleID> + 沙盒变种
  ├── ~/Library/Group Containers/<groupID> (逐个 group ID)
  ├── ~/Library/Logs/<name> + DiagnosticReports 匹配
  ├── ~/Library/Saved Application State/<bundleID>.savedState
  ├── ~/Library/WebKit/<bundleID> + <name>
  ├── ~/Library/LaunchAgents/* 扫描包含 bundleID 的 plist
  ├── ~/Library/Application Scripts/<bundleID>
  └── ~/Library/Mail/ 下模糊匹配 <name>

Step 2: Spotlight 扩展属性 (子线程，超时 2s)
  └── mdfind "kMDItemCFBundleIdentifier == 'com.example.app'"

Step 3: 系统级路径枚举 (串行，只读 2 秒)
  ├── /Library/Application Support/<name>
  ├── /Library/Preferences/<bundleID>.plist
  └── /Library/LaunchAgents + /Library/LaunchDaemons 含 bundleID

Step 4: 结果去重与分类
  └── 按 absoluteURL 去重，确定 category / matchedBy
```

#### 4.2.4 关键规则

| 规则 | 处理 |
|---|---|
| 扫描到符号链接 | 保留目标路径（不扫 link 自身），标记 `isSymlink = true` |
| 扫描遇到无权限目录（如 SIP 保护的 `/Library/...`） | 不报错、不递归，只记录路径存在 → 标记 `isSystemProtected = true` |
| 扫描超时（某个步骤超过预算） | 中止该步骤，已完成的步骤结果照常返回 |
| 同一路径被多条规则命中 | 保留置信度最高的 `matchedBy`，category 取第一个命中的 |
| 返回结果已被删除（扫描过程中消失） | 从最终列表中剔除 |

#### 4.2.5 性能约束

- 标准路径枚举：并发 4 线程，总耗时 ≤ 1.5s
- Spotlight 查询：≤ 2s（`mdfind -onlyin` 限定目录可加速）
- 总扫描预算：**5 秒内必须返回结果**，超时步骤直接放弃

---

### 4.3 模块三：结果列表 UI

#### 4.3.1 Purpose
以可勾选列表展示扫描到的所有待清理文件，让用户决策。

#### 4.3.2 Layout
```
┌──────────────────────────────────────────────────────┐
│  AppSweep                                              │
├──────────────────────────────────────────────────────┤
│  [拖入区域 / 当前 App 信息卡片]                          │
│  名称：XXX.app                                          │
│  Bundle ID：com.xxx.yyy                                │
│  版本：1.2.3    已安装到：/Applications/XXX.app           │
│  预计释放：2.3 GB                                       │
│  [重新扫描]                                             │
├──────────────────────────────────────────────────────┤
│  扫描结果 (23 项 · 总计 2.3 GB)          [全选] [全不选]   │
│  ┌─ 红 · Application Support/  com.xxx.yyy/       1.8 GB │
│  ├─ 红 · Preferences/          com.xxx.yyy.plist   12 KB │
│  ├─ 红 · Caches/               com.xxx.yyy/       400 MB │
│  ├─ 红 · Containers/           com.xxx.yyy/        80 MB │
│  ├─ 橙 · WebKit/               com.xxx.yyy/        30 MB │
│  ├─ 黄 · Logs/                 XXX/                 4 MB │
│  ├─ 灰 · /Downloads/           report.pdf          1.2 MB │
│  └─ ...                                                │
├──────────────────────────────────────────────────────┤
│  已勾选 6 项 · 预计释放 2.29 GB          [开始清理 →]     │
└──────────────────────────────────────────────────────┘
```

#### 4.3.3 交互规则

| 操作 | 行为 |
|---|---|
| 勾选/取消单项 | 底部"已勾选 N 项 · 预计释放 X"实时更新 |
| 点击"全选" | 仅勾选红+橙色 category 项；黄/蓝/灰保持未选 |
| 点击"全不选" | 全部取消 |
| 点击某一行 | 在 Spotlight / Finder 中定位该文件（按住 Option 则在 App 中打开文件） |
| 右键某一行 | 菜单项："在 Finder 中显示"、"打开"、"排除这次扫描"、"始终排除此类" |
| 双击 category 行（如果是目录聚合项） | 展开为该目录下的文件列表 |
| 空扫描结果 | 显示友好文案："没找到这个 App 的残留，已经很干净了 👍" |

---

### 4.4 模块四：删除执行引擎

#### 4.4.1 Purpose
执行用户勾选的删除操作，收集每一项的结果。

#### 4.4.2 Trigger
用户点击底部"开始清理"按钮，按钮变为不可用并显示进度。

#### 4.4.3 执行流程

```
for each checked item (按 category 优先级分组) {
    1. 如果 item.url 不存在 → 记为 skipped("文件不存在")
    2. 如果 item.isSystemProtected →
       弹出 Alert("文件受系统保护：… \n允许 AppSweep 尝试删除？"
                  [仅这次允许] [始终允许(Expert 模式)] [拒绝])
       用户拒绝 → skipped("用户拒绝")
    3. 检查父目录可写权限 → 不可写且不是系统保护 →
       弹出 "无权限删除：… \n你可以尝试管理员权限或在终端手动删除"
    4. FileManager.default.trashItem(at:resultingItemURL)
       → 成功：DeletionRecord(.movedToTrash)
       → 失败：尝试 NSWorkspace.shared.recycle(URLs:)
       → 仍失败：DeletionRecord(.failed(error))
}
汇总 → 打开结果面板
```

#### 4.4.4 关键规则

| 规则 | 处理 |
|---|---|
| 先移废纸篓，不永久删除 | 废纸篓可手动恢复；AppSweep 本身**不**提供"永久删除"按钮 |
| 批量删除时，系统 Alert 可能只弹一次 | Apple Events 授权（`FileUI` entitlements），首次使用时 macOS 弹授权 |
| 遇到 `.app` 本体也被扫描到 | 单独提示："这是 App 本体，已自动取消勾选；如果你确实要卸载它，请确认" |
| 删除过程中 App 被用户终止 | 已成功的文件已在废纸篓，未执行的停止 — 幂等 |
| 用户在清理过程中取消 | 停止后续项，已删的不回滚 |

#### 4.4.5 删除顺序（优先级从高到低）

1. `.caches`、`.preferences`、`.applicationSupport`
2. `.containers`、`.groupContainers`
3. `.webkit`、`.applicationScripts`
4. `.savedState`、`.logs`
5. `.systemLevel`
6. `.downloadsMatched`、`.other`（最后，因为可能是用户自己保留的）

> 理由：前几项删除通常不会影响用户在运行的 App 状态；后几项可能在 App 运行时被锁定。

---

### 4.5 模块五：结果面板

#### 4.5.1 Purpose
清理完成后，让用户清楚知道哪些删了、哪些没删、为什么。

#### 4.5.2 Layout
```
┌─────────────────────────────────┐
│  清理完成                         │
│  目标：XXX.app                    │
│  成功 20 项 · 失败 1 项 · 跳过 2 项 │
│  已释放：2.28 GB                  │
│                                   │
│  ✅ ~/Library/Caches/...    400 MB │
│  ✅ ~/Library/Application Support/... │
│  ✅ ~/Library/Preferences/com...  │
│  ⚠️ /Library/Application Support/ │
│     系统保护，用户拒绝              │
│  ⚠️ ~/Downloads/report.pdf        │
│     非 App 残留，用户跳过           │
│  ❌ ~/Library/Containers/...      │
│     该文件在清理过程中被锁定          │
│                                   │
│  [打开废纸篓]  [关闭]              │
└─────────────────────────────────┘
```

#### 4.5.3 交互

| 操作 | 行为 |
|---|---|
| 点击某一行 | 在 Finder 中定位（若文件还存在）或定位废纸篓 |
| "打开废纸篓" | `NSWorkspace.shared.open(.trashDirectory)` |
| 有失败项 → 显示"重试失败项"按钮 | 只重跑失败和跳过的项 |
| 整体关闭 | 回到主界面，可再扫另一个 App |

---

## 5. 共享规则

### 5.1 安全边界

| 边界 | 处理 |
|---|---|
| 绝不删除 bundle ID 不属于被清理 App 的文件 | 多条 App 的 Containers 可能在同一 group — 只精确匹配 |
| 绝不触碰 `Documents/` `Downloads/` `Movies/` `Music/` `Pictures/` 中**没有** Spotlight 扩展属性证明属于该 App 的文件 | 即使名字模糊也跳过 |
| 绝不尝试删除 `/Applications/<app>.app` 本体，除非用户主动勾选（且二次确认） | 默认自动取消勾选 App 本体 |
| SIP 保护路径（`/System/*`）完全跳过 | 不递归、不报错、不列入扫描结果 |
| 不执行 shell 命令 | 全程用 Swift FileManager / NSWorkspace / Spotlight API |

### 5.2 权限模型

| 权限 | 来源 | 何时需要 |
|---|---|---|
| 访问 `~/Library/` 子目录 | 进程默认继承 | 始终需要（macOS 对 `~/Library` 有 TCC 保护） |
| 访问 `/Library/` | 需要用户在弹窗中允许 | 扫描系统级残留时 |
| Apple Events · Finder | `com.apple.security.automation.apple-events` | `NSWorkspace.recycle` 移废纸篓 |
| Full Disk Access（P1） | 用户在"系统设置 → 隐私与安全"开启 | 当默认权限不够时提示 |

### 5.3 大小计算

- 目录大小：递归汇总子文件大小（并行枚举，超时 1s 则估算）
- 单位：B / KB / MB / GB（十进制，1024 进一，macOS 惯例）
- 显示精度：≥ 1 GB → `X.X GB`；≥ 1 MB → `XXX MB`；否则 `X KB`

### 5.4 排除规则持久化（P1）

- 用户右键选择"始终排除此类"后，该 URL 模式（glob）存入 `~/Library/Application Support/AppSweep/exclusions.json`
- 下次扫描自动跳过

---

## 6. 技术约束（供后续实现参考，非 PRD 决策）

- **平台**：macOS 13 (Ventura) 起（依赖 Spotlight API、`FileManager.trashItem`、Swift Concurrency）
- **语言**：Swift 5.9+，SwiftUI + AppKit 混搭
- **架构**：单 target Swift Package（与用户现有 wtmd/openly/quicklet 风格一致），无外部依赖
- **进程模型**：纯 GUI，不做 XPC 子进程
- **签名与沙盒**：开发阶段用默认开发者证书，`com.apple.security.automation.apple-events` entitlement 开启；App Store 版本后续再评估（会受限）

---

## 7. 未决问题（P0 不阻塞，待后续决策）

| 问题 | 可能影响 | 默认假设 |
|---|---|---|
| 已运行中的 App，其 Containers/Logs 会被锁定，是否自动建议用户先退出该 App？ | 清理成功率 | **是**，若扫描到目标 App 正在运行，在 UI 顶部显示"XXX.app 正在运行，建议先退出以避免清理失败" |
| 是否支持清理 App Store 下载的 App 的 receipt 和 MasReceipts？ | 覆盖率 | **P1 再考虑** |
| "预计释放空间"是否应该包含仍在废纸篓中、之前已被 AppSweep 移走的文件？ | 用户心理 | **不包含**，只计算本次勾选的 |
| 是否提供"导入/导出扫描结果"作为保存清理历史？ | P1 功能 | **否** |

---

*— PRD 完 —*
