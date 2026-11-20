import SwiftUI

@MainActor
struct HistoryView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            content
            Divider().opacity(0.5)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .overlay {
            Rectangle()
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Label("MePaste", systemImage: "clipboard.fill")
                .font(.headline)
            Picker("显示范围", selection: $model.historyScope) {
                ForEach(HistoryScope.allCases, id: \.self) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 160)
            Text(recordCountText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            searchField
            Text(model.canPasteDirectly ? "Return 粘贴" : "Return 复制")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
    }

    private var recordCountText: String {
        let count = model.historyScope == .favorites ? model.favoriteCount : model.records.count
        if model.isSearching {
            return "\(model.filteredRecords.count)/\(count) 条记录"
        }
        return "\(count) 条记录"
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(model.historyScope == .favorites ? "搜索收藏" : "搜索历史", text: $model.searchText)
                .textFieldStyle(.plain)
                .accessibilityLabel("搜索剪贴板记录")
            if model.isSearching {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("清除搜索")
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .frame(width: 220, height: 28)
        .background(Color.primary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        if model.records.isEmpty {
            emptyState(
                symbol: "clipboard",
                title: "暂无剪贴板历史",
                detail: model.isCapturePaused ? "当前已暂停记录，可在菜单栏或设置中恢复" : "复制文本、图片或文件后，记录会显示在这里"
            )
        } else if model.isFiltering {
            ProgressView("正在搜索…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.historyScope == .favorites && model.favoriteCount == 0 {
            emptyState(symbol: "star", title: "暂无收藏", detail: "点击卡片上的星标，常用内容会永久保留")
        } else if model.filteredRecords.isEmpty {
            emptyState(symbol: "magnifyingglass", title: "没有匹配结果", detail: "换个关键词试试")
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14) {
                        ForEach(Array(model.filteredRecords.enumerated()), id: \.element.id) { index, record in
                            ClipboardCard(
                                record: record,
                                isSelected: model.selectedRecordID == record.id,
                                quickPasteNumber: index < 9 ? index + 1 : nil,
                                canPasteDirectly: model.canPasteDirectly,
                                onSelect: { model.select(record) },
                                onPlainText: { model.select(record, asPlainText: true) },
                                onCopy: { model.select(record, copyOnly: true) },
                                onFavorite: { model.toggleFavorite(record) },
                                onDelete: { model.delete(record) }
                            )
                            .id(record.id)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .scrollIndicators(.visible)
                .onChange(of: model.selectedRecordID) { selectedID in
                    guard let selectedID else { return }
                    withAnimation(.easeOut(duration: 0.16)) {
                        proxy.scrollTo(selectedID, anchor: .center)
                    }
                }
            }
        }
    }

    private func emptyState(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Label(model.hotKey.displayName, systemImage: "command")
            Text("← → 选择 · ⌘1–9 快捷操作 · ⇧Return 纯文本")
            Spacer(minLength: 8)
            if let message = model.actionErrorMessage {
                Text(message).foregroundStyle(.red)
            } else {
                if model.isCapturePaused {
                    Label("已暂停记录", systemImage: "pause.circle.fill")
                        .foregroundStyle(.orange)
                }
                if model.canPasteDirectly {
                    Label("直接粘贴", systemImage: "arrow.up.doc")
                } else {
                    Text(model.pasteToActiveApplication ? "未授权辅助功能，当前仅复制" : "仅复制到剪贴板")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .frame(height: 42)
    }
}

private struct ClipboardCard: View {
    let record: ClipboardRecord
    let isSelected: Bool
    let quickPasteNumber: Int?
    let canPasteDirectly: Bool
    let onSelect: () -> Void
    let onPlainText: () -> Void
    let onCopy: () -> Void
    let onFavorite: () -> Void
    let onDelete: () -> Void
    @State private var thumbnail: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let quickPasteNumber {
                    Text("⌘\(quickPasteNumber)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .help("按 ⌘\(quickPasteNumber) 使用此项，按 ⇧⌘\(quickPasteNumber) 使用纯文本")
                }
                Spacer()
                Button(action: onFavorite) {
                    Image(systemName: record.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(record.isFavorite ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(record.isFavorite ? "取消收藏后将重新受历史容量限制" : "收藏并永久保留")
                .accessibilityLabel(record.isFavorite ? "取消收藏" : "收藏并永久保留")
            }

            // The favorite button is outside this gesture so starring an item
            // never pastes it or dismisses the panel.
            VStack(alignment: .leading, spacing: 8) {
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(record.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                HStack {
                    Label(record.subtitle, systemImage: record.kind.symbolName)
                        .lineLimit(1)
                    Spacer()
                    Text(record.createdAt.formatted(.relative(presentation: .numeric)))
                        .lineLimit(1)
                        .help(record.createdAt.formatted())
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onSelect() }
        }
        .padding(12)
        .frame(width: 210, height: 205)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? Color.accentColor : .white.opacity(0.12), lineWidth: 2)
        }
        .task(id: record.id) {
            guard record.kind == .image else { return }
            let image = await ThumbnailCache.shared.thumbnail(for: record)
            guard !Task.isCancelled else { return }
            thumbnail = image
        }
        .contextMenu {
            Button(canPasteDirectly ? "粘贴到原应用" : "复制到剪贴板", action: onSelect)
            Button(canPasteDirectly ? "粘贴为纯文本" : "复制为纯文本", action: onPlainText)
                .disabled(record.plainTextForPasting == nil)
            if canPasteDirectly {
                Button("仅复制到剪贴板", action: onCopy)
            }
            Divider()
            Button(record.isFavorite ? "取消收藏" : "收藏并永久保留", action: onFavorite)
            Divider()
            Button("删除", role: .destructive, action: onDelete)
        }
    }

    @ViewBuilder
    private var preview: some View {
        if record.kind == .image {
            if let thumbnail {
                Image(decorative: thumbnail, scale: 2)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 38))
                    .foregroundStyle(.secondary)
            }
        } else if let text = record.previewText {
            ScrollView {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.disabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                if record.isPreviewTruncated {
                    Text("仅显示部分预览，复制时保留全文")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } else if !record.fileURLs.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 38))
                Text(record.fileURLs.prefix(3).map(\.lastPathComponent).joined(separator: "\n"))
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        } else {
            Image(systemName: record.kind.symbolName)
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
        }
    }
}
