import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var vm: SweepViewModel

    var body: some View {
        VStack(spacing: 0) {
            if !vm.hasFullDiskAccess {
                PermissionBanner()
                Divider()
            }
            if vm.target == nil {
                DropZoneView()
            } else {
                VStack(spacing: 0) {
                    AppHeaderView()
                    Divider()
                    if vm.isScanning {
                        ScanningProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let result = vm.scanResult {
                        if result.items.isEmpty {
                            EmptyScanView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ResultListView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    Divider()
                    BottomBarView()
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let msg = vm.toastMessage {
                Text(msg)
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                    .shadow(radius: 4)
                    .padding(16)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .sheet(isPresented: $vm.showResultPanel) {
            ResultPanelView()
                .environmentObject(vm)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
            return true
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                DispatchQueue.main.async {
                    vm.handleDroppedFile(url: url)
                }
            }
        }
    }
}

// MARK: - 权限提示条

struct PermissionBanner: View {
    @EnvironmentObject var vm: SweepViewModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("未开启「完全磁盘访问权限」")
                    .font(.callout)
                    .fontWeight(.medium)
                Text("部分 App 的残留文件可能扫不到，也无法清理系统级目录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("开启权限") { vm.openFullDiskAccessSettings() }
                .controlSize(.small)
            Button("已开启") { vm.refreshPermissionStatus() }
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.08))
    }
}

// MARK: - 空状态：拖拽区域

struct DropZoneView: View {
    @EnvironmentObject var vm: SweepViewModel
    @State private var isHovering = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isHovering ? Color.accentColor : Color.secondary.opacity(0.3),
                              style: StrokeStyle(lineWidth: isHovering ? 3 : 1.5, dash: [8, 4]))
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(isHovering ? 0.08 : 0.02)))

            VStack(spacing: 20) {
                Image(systemName: "trash")
                    .font(.system(size: 72))
                    .foregroundStyle(isHovering ? Color.accentColor : Color.secondary)

                Text("把 App 拖到这里")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("或")
                    .foregroundStyle(.secondary)

                Button {
                    vm.handleOpenPanel()
                } label: {
                    Text("浏览选择…")
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)

                Text("AppSweep 会扫描该 App 产生的缓存、偏好设置、容器数据等全部残留文件")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: $isHovering) { providers in
            if let provider = providers.first {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        DispatchQueue.main.async {
                            vm.handleDroppedFile(url: url)
                        }
                    }
                }
            }
            return true
        }
    }
}

// MARK: - App 信息卡片

struct AppHeaderView: View {
    @EnvironmentObject var vm: SweepViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            if let target = vm.target {
                Group {
                    if let icon = target.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 64, height: 64)
                    } else {
                        Image(systemName: "app.badge")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                            .frame(width: 64, height: 64)
                    }
                }
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)

                VStack(alignment: .leading, spacing: 4) {
                    Text(target.displayName)
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(target.bundleID)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Text("v\(target.version)")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(4)
                        if target.isRunning {
                            Text("正在运行")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.12))
                                .cornerRadius(4)
                        }
                        if target.isSystemApp {
                            Text("系统 App")
                                .font(.caption)
                                .foregroundStyle(.purple)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.12))
                                .cornerRadius(4)
                        }
                    }
                    Text(target.bundleURL.path)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    if let r = vm.scanResult {
                        Text("共 \(r.items.count) 项")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(humanSize(r.totalSize))
                            .font(.headline)
                    }
                    Button {
                        vm.clearAll()
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.plain)
                    .help("重新选择 App")
                }
            }
        }
        .padding(16)
    }
}

// MARK: - 扫描中

struct ScanningProgressView: View {
    @EnvironmentObject var vm: SweepViewModel

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
            Text(vm.scanStep ?? "正在扫描残留文件…")
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: vm.scanStep)
        }
    }
}

// MARK: - 空扫描结果

struct EmptyScanView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("扫描完成")
                .font(.title3)
                .fontWeight(.semibold)
            Text("没找到残留文件，这个 App 很干净")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 结果列表

struct ResultListView: View {
    @EnvironmentObject var vm: SweepViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("扫描结果 · \(vm.scanResult?.items.count ?? 0) 项 · \(humanSize(vm.scanResult?.totalSize ?? 0))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("建议全选") { vm.selectAllRedOrange() }
                Button("全不选") { vm.deselectAll() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.04))

            List {
                ForEach(vm.scanResult?.items ?? []) { item in
                    ItemRow(item: item)
                        .contentShape(Rectangle())
                        .onTapGesture { vm.toggleCheck(item) }
                        .contextMenu {
                            Button("在 Finder 中显示") { vm.revealInFinder(item.url) }
                            Button("打开") {
                                NSWorkspace.shared.open(item.url)
                            }
                            Divider()
                            Button("取消勾选此类型") {
                                // 取消同 category 的所有
                                if let result = vm.scanResult {
                                    for other in result.items where other.category == item.category {
                                        vm.checkedIDs.remove(other.id)
                                    }
                                }
                            }
                        }
                }
            }
            .listStyle(.inset)
        }
    }
}

struct ItemRow: View {
    @EnvironmentObject var vm: SweepViewModel
    let item: ScannedItem

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { vm.checkedIDs.contains(item.id) },
                set: { _ in vm.toggleCheck(item) }
            ))
            .labelsHidden()

            // 颜色标签
            Circle()
                .fill(Color(nsColor: item.category.semanticNSColor))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.url.lastPathComponent)
                        .font(.body)
                    if item.isSymlink {
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if item.isSystemProtected {
                        Image(systemName: "lock.shield")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                    }
                }
                HStack(spacing: 8) {
                    Text(item.category.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.url.path)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(humanSize(item.size))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 底部操作栏

struct BottomBarView: View {
    @EnvironmentObject var vm: SweepViewModel

    var body: some View {
        HStack {
            Text("已勾选 \(vm.checkedItems.count) 项 · 预计释放 \(humanSize(vm.checkedTotalSize))")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()

            if vm.isDeleting {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    if let p = vm.deletionProgress {
                        Text("正在清理 \(p.done)/\(p.total)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            } else {
                Button {
                    vm.startDeletion()
                } label: {
                    Label("开始清理", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.checkedItems.isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.04))
    }
}

// MARK: - 结果面板

struct ResultPanelView: View {
    @EnvironmentObject var vm: SweepViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("清理完成")
                .font(.title2)
                .fontWeight(.bold)
            HStack(spacing: 18) {
                stat(label: "成功", value: "\(vm.successCount)", color: .green, icon: "checkmark.circle")
                stat(label: "失败", value: "\(vm.failedCount)", color: .red, icon: "xmark.circle")
                stat(label: "跳过", value: "\(vm.skippedCount)", color: .orange, icon: "minus.circle")
                Spacer()
                Text("已释放 \(humanSize(vm.deletionRecords.filter(\.isSuccess).map { $0.item.size }.reduce(0, +)))")
                    .font(.headline)
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private func stat(label: String, value: String, color: Color, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(color)
            Text("\(label) \(value)").font(.callout)
        }
    }

    private var list: some View {
        List {
            ForEach(vm.deletionRecords) { record in
                recordRow(record)
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func recordRow(_ record: DeletionRecord) -> some View {
        let (icon, color, detail) = outcomeMeta(record)
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.item.url.lastPathComponent)
                    .font(.body)
                Text(record.item.url.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 220, alignment: .trailing)
        }
    }

    private func outcomeMeta(_ record: DeletionRecord) -> (String, Color, String) {
        switch record.outcome {
        case .movedToTrash:
            return ("checkmark.circle", .green, humanSize(record.item.size))
        case .skipped(let reason):
            return ("minus.circle", .orange, reason.rawValue)
        case .failed(let err):
            return ("xmark.circle", .red, err)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("打开废纸篓") { vm.openTrash() }
            Button("关闭") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }
}
