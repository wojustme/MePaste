import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ExcludedApplicationsSettings: View {
    @ObservedObject var model: AppModel
    @State private var invalidApplicationMessage: String?

    var body: some View {
        if model.excludedApplications.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "app.badge.checkmark")
                    .foregroundStyle(.secondary)
                Text("尚未排除任何应用")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.excludedApplications) { application in
                        ExcludedApplicationRow(application: application) {
                            model.removeExcludedApplication(application)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 160)
        }
        Button {
            chooseApplications()
        } label: {
            Label("添加应用…", systemImage: "plus.app")
        }
        .controlSize(.small)
        if let invalidApplicationMessage {
            Text(invalidApplicationMessage)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func chooseApplications() {
        invalidApplicationMessage = nil
        let panel = NSOpenPanel()
        panel.title = "选择不记录的应用"
        panel.prompt = "添加"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                if let application = ExcludedApplication(url: url) {
                    model.excludeApplication(application)
                } else {
                    invalidApplicationMessage = "无法读取 \(url.lastPathComponent) 的应用标识。"
                }
            }
        }
    }
}

@MainActor
private struct ExcludedApplicationRow: View {
    let application: ExcludedApplication
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            if let icon = AppIconCache.shared.icon(forBundleIdentifier: application.bundleIdentifier) {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
            }

            VStack(alignment: .leading, spacing: 1.5) {
                Text(application.name)
                    .font(.system(size: 12.5, weight: .medium))
                Text(application.bundleIdentifier)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(isHovered ? Color.red.opacity(0.85) : Color.secondary.opacity(0.65))
            }
            .buttonStyle(.borderless)
            .help("恢复记录 \(application.name)")
            .accessibilityLabel("移除排除：\(application.name)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { isHovered = $0 }
    }
}
