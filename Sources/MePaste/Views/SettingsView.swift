import AppKit
import SwiftUI

@MainActor
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var confirmsClearHistory = false
    @State private var confirmsDeleteEverything = false

    var body: some View {
        TabView {
            generalSettings
                .tabItem { Label("通用", systemImage: "gearshape") }
            shortcutSettings
                .tabItem { Label("快捷键", systemImage: "keyboard") }
            historySettings
                .tabItem { Label("历史与收藏", systemImage: "star") }
            privacySettings
                .tabItem { Label("隐私", systemImage: "hand.raised") }
        }
        .padding(12)
        .frame(width: 560, height: 540)
        .onAppear(perform: refreshSystemSettings)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshSystemSettings()
        }
    }

    private var generalSettings: some View {
        Form {
            Section("启动") {
                LaunchAtLoginSettings(manager: model.launchAtLoginManager)
            }
            Section("粘贴方式") {
                Toggle("选中记录后直接粘贴到原应用", isOn: $model.pasteToActiveApplication)
                Text("未授权或关闭此选项时，仍会复制到剪贴板并返回原应用，按 ⌘V 即可粘贴。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("辅助功能权限") {
                    Label(
                        model.isAccessibilityTrusted ? "已授权" : "未授权 · 仅复制可用",
                        systemImage: model.isAccessibilityTrusted ? "checkmark.circle.fill" : "info.circle"
                    )
                    .foregroundStyle(model.isAccessibilityTrusted ? Color.green : Color.secondary)
                }
                HStack {
                    Button("授权辅助功能…") { model.requestAccessibilityPermission() }
                        .disabled(model.isAccessibilityTrusted)
                    Button("打开系统设置…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
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
                        .frame(width: 150, height: 28)
                }
                if let message = model.hotKeyErrorMessage {
                    Text(message).font(.caption).foregroundStyle(.red)
                } else {
                    HStack {
                        Text("点击快捷键区域后，按下新的组合键。")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("恢复默认") { model.resetHotKey() }
                            .disabled(model.hotKey == .default)
                    }
                    .font(.caption)
                }
            }
            Section("历史面板内") {
                LabeledContent("选择记录", value: "← / →")
                LabeledContent("使用选中记录", value: "Return")
                LabeledContent("使用纯文本", value: "⇧Return")
                LabeledContent("使用前九条记录", value: "⌘1 … ⌘9")
                LabeledContent("前九条记录转为纯文本", value: "⇧⌘1 … ⇧⌘9")
                LabeledContent("清除搜索 / 关闭面板", value: "Esc")
                Text("编号始终对应当前列表（包括搜索结果和收藏）的前九条记录。图片等无法转为纯文本的内容不会覆盖剪贴板。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var historySettings: some View {
        Form {
            Section("普通历史容量") {
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
            Section("数据") {
                LabeledContent("普通历史", value: "\(model.ordinaryRecordCount) 条")
                LabeledContent("永久收藏", value: "\(model.favoriteCount) 条")
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
        .formStyle(.grouped)
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
                Text("自动忽略带有敏感、临时或自动生成标记的剪贴板内容。未标记的敏感内容无法保证识别，请使用应用排除或暂停记录。所有历史仍仅保存在本机。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
