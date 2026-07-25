import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("通用") {
                LaunchAtLoginSettings(manager: model.launchAtLoginManager)
            }

            Section("快捷键") {
                LabeledContent("显示剪贴板历史") {
                    HotKeyRecorder(hotKey: model.hotKey) {
                        model.updateHotKey($0)
                    }
                    .frame(width: 150, height: 28)
                }

                if let message = model.hotKeyErrorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    HStack {
                        Text("点击快捷键区域后，按下新的组合键。")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("恢复默认") {
                            model.resetHotKey()
                        }
                        .disabled(model.hotKey == .default)
                    }
                    .font(.caption)
                }
            }

            Section("历史容量") {
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

                Text("记录同时受时间和数量限制，任一条件达到后都会自动清理。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("数据") {
                HStack {
                    Text("当前共保存 \(model.records.count) 条记录")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("清空历史", role: .destructive) {
                        model.clearHistory()
                    }
                    .disabled(model.records.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 500)
        .onAppear {
            model.launchAtLoginManager.refresh()
        }
    }
}

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
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
        } else {
            Text("使用打包后的 MePaste.app 时可注册为系统登录项。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
