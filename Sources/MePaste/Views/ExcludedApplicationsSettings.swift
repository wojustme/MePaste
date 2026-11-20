import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ExcludedApplicationsSettings: View {
    @ObservedObject var model: AppModel
    @State private var invalidApplicationMessage: String?

    var body: some View {
        if model.excludedApplications.isEmpty {
            Text("尚未排除任何应用")
                .foregroundStyle(.secondary)
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(model.excludedApplications) { application in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(application.name)
                                Text(application.bundleIdentifier)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Spacer()
                            Button {
                                model.removeExcludedApplication(application)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("恢复记录 \(application.name)")
                            .accessibilityLabel("移除排除：\(application.name)")
                        }
                    }
                }
            }
            .frame(maxHeight: 150)
        }
        Button("添加应用…", action: chooseApplications)
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
