import AppKit
import SwiftUI

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case shortcut
    case history
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .shortcut: return "快捷键"
        case .history: return "历史与收藏"
        case .privacy: return "隐私"
        }
    }

    var symbolName: String {
        switch self {
        case .general: return "gearshape.fill"
        case .shortcut: return "command"
        case .history: return "star.fill"
        case .privacy: return "hand.raised.fill"
        }
    }

    var accent: Color {
        switch self {
        case .general: return .blue
        case .shortcut: return .indigo
        case .history: return .orange
        case .privacy: return .teal
        }
    }
}

@MainActor
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var selectedTab: SettingsTab = .general
    @State private var confirmsClearHistory = false
    @State private var confirmsDeleteEverything = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            settingsHeader
            Divider().opacity(0.6)
            Group {
                switch selectedTab {
                case .general:
                    generalSettings
                case .shortcut:
                    shortcutSettings
                case .history:
                    historySettings
                case .privacy:
                    privacySettings
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 620, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: refreshSystemSettings)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshSystemSettings()
        }
    }

    private var settingsHeader: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.27, green: 0.50, blue: 0.98),
                                    Color(red: 0.45, green: 0.36, blue: 0.96)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                        .shadow(color: Color.accentColor.opacity(0.28), radius: 6, y: 2)
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text("MePaste 设置")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                        Text(AppVersion.current)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Capsule())
                    }
                    Text("轻量、私密的本地剪贴板历史工具")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if model.isCapturePaused {
                    StatusPill(title: "已暂停记录", tint: .orange, symbol: "pause.circle.fill")
                } else {
                    StatusPill(title: "正在记录", tint: .green)
                }
            }
            .padding(.top, 28)

            HStack(spacing: 6) {
                ForEach(SettingsTab.allCases) { tab in
                    tabButton(tab)
                }
            }
            .padding(4)
            .background(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .background(.ultraThinMaterial)
    }

    private func tabButton(_ tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(.easeOut(duration: 0.16)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? tab.accent : .secondary)
                Text(tab.title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.07), radius: 2, y: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var generalSettings: some View {
        Form {
            Section("启动与运行") {
                LaunchAtLoginSettings(manager: model.launchAtLoginManager)
            }
            Section("粘贴方式") {
                Toggle("选中记录后直接粘贴到原应用", isOn: $model.pasteToActiveApplication)
                Text("未授权或关闭此选项时，仍会复制到剪贴板并返回原应用，按 ⌘V 即可粘贴。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("辅助功能权限") {
                    StatusPill(
                        title: model.isAccessibilityTrusted ? "已授权" : "未授权 · 仅复制可用",
                        tint: model.isAccessibilityTrusted ? .green : .secondary,
                        symbol: model.isAccessibilityTrusted ? "checkmark.circle.fill" : "info.circle"
                    )
                }
                HStack(spacing: 10) {
                    Button("授权辅助功能…") { model.requestAccessibilityPermission() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(model.isAccessibilityTrusted)
                    Button("打开系统设置…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }
                Text("建议安装打包后的 MePaste.app 再授权；授权完成后回到此窗口会自动刷新状态。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var shortcutSettings: some View {
        Form {
            Section("全局快捷键") {
                LabeledContent("显示剪贴板历史") {
                    HotKeyRecorder(hotKey: model.hotKey) { model.updateHotKey($0) }
                        .frame(width: 164, height: 30)
                }
                if let message = model.hotKeyErrorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    HStack {
                        Text("点击录制框后，按下新的组合键即可修改（Esc 取消）。")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("恢复默认") { model.resetHotKey() }
                            .controlSize(.small)
                            .disabled(model.hotKey == .default)
                    }
                    .font(.caption)
                }
            }
            Section("历史面板内快捷键") {
                shortcutRow("选择上一条 / 下一条记录", keys: ["←", "→"])
                shortcutRow("粘贴 / 复制选中记录", keys: ["↩"])
                shortcutRow("以纯文本粘贴 / 复制", keys: ["⇧", "↩"])
                shortcutRow("快速使用前九条记录", keys: ["⌘1", "…", "⌘9"])
                shortcutRow("前九条记录转为纯文本", keys: ["⇧⌘1", "…", "⇧⌘9"])
                shortcutRow("清除搜索 / 筛选或关闭面板", keys: ["Esc"])
                Text("编号始终对应当前列表（包括搜索结果、类型筛选和收藏）的前九条记录。图片等无法转为纯文本的内容不会覆盖剪贴板。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func shortcutRow(_ title: String, keys: [String]) -> some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                    if key == "…" {
                        Text("…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        KeyCapBadge(text: key)
                    }
                }
            }
        }
    }

    private var historySettings: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    metricCard(
                        title: "普通历史",
                        value: "\(model.ordinaryRecordCount)",
                        unit: model.maximumRecordCount > 0 ? "/ \(model.maximumRecordCount) 条" : "条 · 无上限",
                        symbol: "clock.fill",
                        tint: .blue,
                        progress: model.maximumRecordCount > 0
                            ? min(1.0, Double(model.ordinaryRecordCount) / Double(model.maximumRecordCount))
                            : nil
                    )
                    metricCard(
                        title: "永久收藏",
                        value: "\(model.favoriteCount)",
                        unit: "条 · 不占历史配额",
                        symbol: "star.fill",
                        tint: .orange,
                        progress: nil
                    )
                }
                .padding(.vertical, 4)
            }

            Section("普通历史容量策略") {
                Picker("最长保留时间", selection: $model.maximumAgeDays) {
                    Text("1 天").tag(1)
                    Text("7 天").tag(7)
                    Text("30 天").tag(30)
                    Text("90 天").tag(90)
                    Text("永久").tag(0)
                }
                Picker("最大记录数量", selection: $model.maximumRecordCount) {
                    Text("100 条").tag(100)
                    Text("500 条").tag(500)
                    Text("1,000 条").tag(1_000)
                    Text("5,000 条").tag(5_000)
                    Text("不限制").tag(0)
                }
                Text("普通历史同时受时间和数量限制。收藏永久保留，不占普通历史额度；取消收藏后将重新按容量策略清理。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("数据清理") {
                HStack(spacing: 10) {
                    Button("清空普通历史…", role: .destructive) { confirmsClearHistory = true }
                        .disabled(model.ordinaryRecordCount == 0)
                        .alert("清空普通历史？", isPresented: $confirmsClearHistory) {
                            Button("取消", role: .cancel) {}
                            Button("清空历史", role: .destructive) { model.clearHistory() }
                        } message: {
                            Text("收藏会保留，其余记录将被删除。此操作不可撤销。")
                        }

                    Button("删除全部记录（含收藏）…", role: .destructive) { confirmsDeleteEverything = true }
                        .disabled(model.records.isEmpty)
                        .alert("删除全部记录及收藏？", isPresented: $confirmsDeleteEverything) {
                            Button("取消", role: .cancel) {}
                            Button("删除全部", role: .destructive) { model.clearHistory(includeFavorites: true) }
                        } message: {
                            Text("这也会删除永久收藏，且不可撤销。")
                        }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func metricCard(
        title: String,
        value: String,
        unit: String,
        symbol: String,
        tint: Color,
        progress: Double?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                Text(unit)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let progress {
                ProgressView(value: progress)
                    .tint(progress > 0.9 ? .orange : tint)
            } else {
                Spacer(minLength: 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(colorScheme == .dark ? 0.12 : 0.065))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(tint.opacity(0.18), lineWidth: 0.75)
        }
    }

    private var privacySettings: some View {
        Form {
            Section("采集控制") {
                Toggle("暂停记录剪贴板", isOn: $model.isCapturePaused)
                Text("暂停不影响使用已有历史；恢复时不会补录暂停期间的内容。重启应用后仍保持暂停。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("不记录这些应用") {
                ExcludedApplicationsSettings(model: model)
                Text("按采集时的前台应用判断，仅影响新复制的内容，不会删除已有历史。浏览器内的敏感内容可通过排除整个浏览器来保护。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.teal)
                        .padding(.top, 1)
                    Text("自动忽略带有敏感、临时或自动生成标记的剪贴板内容（如密码管理器）。未标记的敏感内容无法保证识别，请使用应用排除或暂停记录。所有历史均仅保存在本机。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func refreshSystemSettings() {
        model.launchAtLoginManager.refresh()
        model.refreshAccessibilityPermission()
    }
}

@MainActor
private struct LaunchAtLoginSettings: View {
    @ObservedObject var manager: LaunchAtLoginManager

    var body: some View {
        Toggle(
            "登录时自动启动",
            isOn: Binding(
                get: { manager.isEnabled },
                set: { manager.setEnabled($0) }
            )
        )
        if let errorMessage = manager.errorMessage {
            Text(errorMessage).font(.caption).foregroundStyle(.red)
        } else {
            Text("使用打包后的 MePaste.app 时可注册为系统登录项。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
