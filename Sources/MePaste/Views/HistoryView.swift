import SwiftUI

@MainActor
struct HistoryView: View {
    @ObservedObject var model: AppModel
    @FocusState private var isSearchFocused: Bool
    @State private var referenceDate = Date()
    @Environment(\.colorScheme) private var colorScheme

    private let dockCornerRadius: CGFloat = 22

    var body: some View {
        VStack(spacing: 0) {
            header
            hairlineDivider
            content
            hairlineDivider
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { dockBackground }
        .clipShape(RoundedRectangle(cornerRadius: dockCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: dockCornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.24 : 0.72),
                            Color.white.opacity(colorScheme == .dark ? 0.08 : 0.25)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        }
        .task {
            // Refresh relative timestamps gently only while the panel is visible.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                referenceDate = Date()
            }
        }
    }

    private var dockBackground: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.06 : 0.35),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .center
            )
        }
    }

    private var hairlineDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.1 : 0.07))
            .frame(height: 1)
    }

    private var header: some View {
        HStack(spacing: 12) {
            brandBadge
            scopeSwitcher
            kindFilterBar
            Spacer(minLength: 8)
            searchField
            headerActions
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
    }

    private var brandBadge: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
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
                    .frame(width: 26, height: 26)
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text("MePaste")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
        }
    }

    private var scopeSwitcher: some View {
        HStack(spacing: 2) {
            scopeButton(.all, count: model.records.count, icon: "clock")
            scopeButton(.favorites, count: model.favoriteCount, icon: "star.fill")
        }
        .padding(3)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func scopeButton(_ scope: HistoryScope, count: Int, icon: String) -> some View {
        let isSelected = model.historyScope == scope
        return Button {
            withAnimation(.easeOut(duration: 0.16)) {
                model.historyScope = scope
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(scope == .favorites && isSelected ? Color.orange : (isSelected ? Color.accentColor : Color.secondary))
                Text(scope.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                Text("\(count)")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(isSelected ? Color.primary.opacity(0.72) : Color.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(isSelected ? 0.08 : 0.05))
                    .clipShape(Capsule())
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.72 : 0.95))
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.08), radius: 2, y: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var kindFilterBar: some View {
        HStack(spacing: 4) {
            kindChip(nil, title: "全部", symbol: "square.grid.2x2")
            kindChip(.text, title: "文本", symbol: "text.alignleft")
            kindChip(.image, title: "图片", symbol: "photo")
            kindChip(.files, title: "文件", symbol: "doc.on.doc")
        }
    }

    private func kindChip(_ kind: ClipboardKind?, title: String, symbol: String) -> some View {
        let isSelected = model.kindFilter == kind
        return Button {
            withAnimation(.easeOut(duration: 0.14)) {
                model.kindFilter = isSelected && kind != nil ? nil : kind
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 10.5, weight: .medium))
                Text(title)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4.5)
            .background(
                isSelected
                    ? Color.accentColor.opacity(colorScheme == .dark ? 0.2 : 0.12)
                    : Color.clear
            )
            .clipShape(Capsule())
            .overlay {
                if isSelected {
                    Capsule()
                        .strokeBorder(Color.accentColor.opacity(0.32), lineWidth: 0.75)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSearchFocused ? Color.accentColor : Color.secondary)
            TextField(model.historyScope == .favorites ? "搜索收藏…" : "搜索剪贴板历史…", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($isSearchFocused)
                .accessibilityLabel("搜索剪贴板记录")
            if model.isSearching && !model.isFiltering {
                Text("\(model.filteredRecords.count)")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(Capsule())
            }
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("清除搜索")
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 232, height: 30)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.1 : 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(
                    isSearchFocused ? Color.accentColor.opacity(0.75) : Color.primary.opacity(0.1),
                    lineWidth: isSearchFocused ? 1.5 : 0.75
                )
        }
    }

    private var headerActions: some View {
        HStack(spacing: 6) {
            Button {
                model.isCapturePaused.toggle()
            } label: {
                Image(systemName: model.isCapturePaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(model.isCapturePaused ? Color.orange : Color.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        model.isCapturePaused
                            ? Color.orange.opacity(colorScheme == .dark ? 0.2 : 0.14)
                            : Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(model.isCapturePaused ? "已暂停记录，点击恢复" : "暂停记录剪贴板")
            .accessibilityLabel(model.isCapturePaused ? "恢复记录剪贴板" : "暂停记录剪贴板")

            Button {
                model.openSettings()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("打开 MePaste 设置")
            .accessibilityLabel("打开设置")
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.records.isEmpty {
            emptyState(
                symbol: model.isCapturePaused ? "pause.circle" : "doc.on.clipboard",
                tint: model.isCapturePaused ? .orange : .accentColor,
                title: "暂无剪贴板历史",
                detail: model.isCapturePaused ? "当前已暂停记录，恢复后会自动捕获新的复制内容" : "复制文本、代码、链接、图片或文件后，会立即出现在这里",
                actionTitle: model.isCapturePaused ? "恢复记录" : nil,
                action: model.isCapturePaused ? { model.isCapturePaused = false } : nil
            )
        } else if model.isFiltering {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.regular)
                Text("正在检索历史记录…")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.historyScope == .favorites && model.favoriteCount == 0 {
            emptyState(
                symbol: "star",
                tint: .orange,
                title: "暂无收藏内容",
                detail: "点击卡片右上角的星标，将常用片段永久保留在收藏中",
                actionTitle: "查看全部历史",
                action: { model.historyScope = .all }
            )
        } else if model.filteredRecords.isEmpty {
            emptyState(
                symbol: "magnifyingglass",
                tint: .secondary,
                title: "没有找到匹配的记录",
                detail: model.kindFilter != nil ? "当前已按类型筛选，试试切换类型或修改关键词" : "换个关键词试试，支持空格分隔多词匹配",
                actionTitle: "清除筛选条件",
                action: {
                    model.searchText = ""
                    model.kindFilter = nil
                }
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(model.filteredRecords) { record in
                            ClipboardCard(
                                record: record,
                                isSelected: model.selectedRecordID == record.id,
                                quickPasteNumber: model.quickPasteNumber(for: record.id),
                                canPasteDirectly: model.canPasteDirectly,
                                referenceDate: referenceDate,
                                actions: ClipboardCardActions(
                                    onSelect: { model.select(record) },
                                    onPlainText: { model.select(record, asPlainText: true) },
                                    onCopy: { model.select(record, copyOnly: true) },
                                    onFavorite: { model.toggleFavorite(record) },
                                    onDelete: { model.delete(record) }
                                )
                            )
                            .equatable()
                            .id(record.id)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                }
                .onAppear {
                    guard let selectedID = model.selectedRecordID else { return }
                    proxy.scrollTo(selectedID, anchor: .center)
                }
                .onChange(of: model.selectedRecordID) { selectedID in
                    guard let selectedID else { return }
                    withAnimation(.easeOut(duration: 0.16)) {
                        proxy.scrollTo(selectedID, anchor: .center)
                    }
                }
            }
        }
    }

    private func emptyState(
        symbol: String,
        tint: Color,
        title: String,
        detail: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(tint.opacity(colorScheme == .dark ? 0.18 : 0.11))
                    .frame(width: 56, height: 56)
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(tint)
            }
            Text(title)
                .font(.system(size: 14.5, weight: .semibold))
            Text(detail)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            HStack(spacing: 10) {
                shortcutHint(key: model.hotKey.displayName, label: "呼出")
                shortcutHint(key: "← →", label: "选择")
                shortcutHint(key: "↩", label: model.canPasteDirectly ? "粘贴" : "复制")
                shortcutHint(key: "⇧↩", label: "纯文本")
                shortcutHint(key: "⌘1–9", label: "速贴")
            }
            Spacer(minLength: 8)
            if let message = model.actionErrorMessage {
                StatusPill(title: message, tint: .red, symbol: "exclamationmark.triangle.fill")
            } else {
                HStack(spacing: 8) {
                    if model.isCapturePaused {
                        StatusPill(title: "已暂停记录", tint: .orange, symbol: "pause.circle.fill")
                    }
                    if model.canPasteDirectly {
                        StatusPill(title: "直接粘贴已就绪", tint: .green)
                    } else {
                        StatusPill(
                            title: model.pasteToActiveApplication ? "未授权辅助功能 · 仅复制" : "仅复制模式",
                            tint: .secondary
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 40)
    }

    private func shortcutHint(key: String, label: String) -> some View {
        HStack(spacing: 4) {
            KeyCapBadge(text: key)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

private struct ClipboardCardActions {
    let onSelect: () -> Void
    let onPlainText: () -> Void
    let onCopy: () -> Void
    let onFavorite: () -> Void
    let onDelete: () -> Void
}

private struct ClipboardCard: View, Equatable {
    let record: ClipboardRecord
    let isSelected: Bool
    let quickPasteNumber: Int?
    let canPasteDirectly: Bool
    let referenceDate: Date
    let actions: ClipboardCardActions

    @State private var thumbnail: CGImage?
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    init(
        record: ClipboardRecord,
        isSelected: Bool,
        quickPasteNumber: Int?,
        canPasteDirectly: Bool,
        referenceDate: Date,
        actions: ClipboardCardActions
    ) {
        self.record = record
        self.isSelected = isSelected
        self.quickPasteNumber = quickPasteNumber
        self.canPasteDirectly = canPasteDirectly
        self.referenceDate = referenceDate
        self.actions = actions
        // Synchronous cache hit avoids any placeholder flicker on panel open.
        _thumbnail = State(
            initialValue: record.kind == .image ? ThumbnailCache.shared.cachedThumbnail(for: record.id) : nil
        )
    }

    nonisolated static func == (lhs: ClipboardCard, rhs: ClipboardCard) -> Bool {
        lhs.record.id == rhs.record.id
            && lhs.record.createdAt == rhs.record.createdAt
            && lhs.record.isFavorite == rhs.record.isFavorite
            && lhs.isSelected == rhs.isSelected
            && lhs.quickPasteNumber == rhs.quickPasteNumber
            && lhs.canPasteDirectly == rhs.canPasteDirectly
            && lhs.referenceDate == rhs.referenceDate
    }

    private var category: ClipboardVisualCategory {
        ClipboardVisualCategory(record: record)
    }

    private var cardCornerRadius: CGFloat { 15 }

    var body: some View {
        let visualCategory = category
        let accent = visualCategory.accentColor

        VStack(alignment: .leading, spacing: 0) {
            cardHeader(category: visualCategory, accent: accent)

            // The favorite & hover action buttons stay outside this tap area so
            // starring/deleting an item never pastes it or dismisses the panel.
            VStack(alignment: .leading, spacing: 8) {
                preview(category: visualCategory, accent: accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                cardFooter
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .contentShape(Rectangle())
            .onTapGesture(perform: actions.onSelect)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { actions.onSelect() }
        }
        .frame(width: 238, height: 242)
        .background { cardSurface }
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if isHovered {
                hoverActionStrip
                    .padding(.trailing, 9)
                    .padding(.bottom, 34)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isSelected ? 2 : (isHovered ? 1.25 : 0.85))
        }
        .shadow(
            color: isSelected
                ? Color.accentColor.opacity(colorScheme == .dark ? 0.34 : 0.22)
                : Color.black.opacity(colorScheme == .dark ? (isHovered ? 0.34 : 0.22) : (isHovered ? 0.12 : 0.06)),
            radius: isSelected ? 10 : (isHovered ? 8 : 4),
            y: isSelected ? 4 : (isHovered ? 3 : 2)
        )
        .scaleEffect(isHovered && !isSelected ? 1.012 : 1.0)
        .animation(.easeOut(duration: 0.14), value: isHovered)
        .animation(.easeOut(duration: 0.14), value: isSelected)
        .onHover { hovering in
            isHovered = hovering
        }
        .task(id: record.id) {
            guard record.kind == .image, thumbnail == nil else { return }
            let image = await ThumbnailCache.shared.thumbnail(for: record)
            guard !Task.isCancelled else { return }
            thumbnail = image
        }
        .contextMenu {
            Button(canPasteDirectly ? "粘贴到原应用" : "复制到剪贴板", action: actions.onSelect)
            Button(canPasteDirectly ? "粘贴为纯文本" : "复制为纯文本", action: actions.onPlainText)
                .disabled(record.plainTextForPasting == nil)
            if canPasteDirectly {
                Button("仅复制到剪贴板", action: actions.onCopy)
            }
            Divider()
            Button(record.isFavorite ? "取消收藏" : "收藏并永久保留", action: actions.onFavorite)
            Divider()
            Button("删除", role: .destructive, action: actions.onDelete)
        }
    }

    private var cardSurface: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
                .opacity(colorScheme == .dark ? (isSelected ? 0.78 : 0.62) : (isSelected ? 0.96 : 0.86))
            if isSelected {
                Color.accentColor.opacity(colorScheme == .dark ? 0.14 : 0.07)
            }
        }
    }

    private var borderColor: Color {
        if isSelected {
            return Color.accentColor
        }
        if isHovered {
            return Color.primary.opacity(colorScheme == .dark ? 0.28 : 0.2)
        }
        return Color.primary.opacity(colorScheme == .dark ? 0.13 : 0.09)
    }

    private func cardHeader(category: ClipboardVisualCategory, accent: Color) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: category.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
                Text(category.label)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.88))
            }
            Spacer(minLength: 4)
            if let quickPasteNumber {
                KeyCapBadge(text: "⌘\(quickPasteNumber)", prominent: isSelected)
                    .help("按 ⌘\(quickPasteNumber) 使用此项，按 ⇧⌘\(quickPasteNumber) 使用纯文本")
            }
            Button(action: actions.onFavorite) {
                Image(systemName: record.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(record.isFavorite ? Color.orange : Color.secondary.opacity(0.8))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(record.isFavorite ? "取消收藏后将重新受历史容量限制" : "收藏并永久保留")
            .accessibilityLabel(record.isFavorite ? "取消收藏" : "收藏并永久保留")
        }
        .padding(.horizontal, 11)
        .frame(height: 35)
        .background(accent.opacity(colorScheme == .dark ? 0.16 : 0.10))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(accent.opacity(colorScheme == .dark ? 0.22 : 0.14))
                .frame(height: 0.75)
        }
    }

    private var hoverActionStrip: some View {
        HStack(spacing: 4) {
            if record.plainTextForPasting != nil {
                cardActionButton(
                    symbol: "doc.plaintext",
                    help: canPasteDirectly ? "粘贴为纯文本 (⇧↩)" : "复制为纯文本 (⇧↩)",
                    action: actions.onPlainText
                )
            }
            cardActionButton(
                symbol: "doc.on.doc",
                help: "仅复制到剪贴板",
                action: actions.onCopy
            )
            cardActionButton(
                symbol: "trash",
                help: "删除此记录",
                tint: .red,
                action: actions.onDelete
            )
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
    }

    private func cardActionButton(
        symbol: String,
        help: String,
        tint: Color = .primary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(tint.opacity(0.85))
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var cardFooter: some View {
        HStack(spacing: 6) {
            Text(record.subtitle)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Text(RelativeTimeFormatter.string(from: record.createdAt, relativeTo: referenceDate))
                .lineLimit(1)
                .help(record.createdAt.formatted())
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func preview(category: ClipboardVisualCategory, accent: Color) -> some View {
        switch category {
        case .color(let colorValue):
            colorPreview(colorValue)
        case .image:
            imagePreview
        case .link:
            linkPreview(accent: accent)
        case .files:
            filesPreview(accent: accent)
        case .code, .text:
            textPreview(isCode: record.isCodeLike)
        case .other:
            otherPreview
        }
    }

    private func colorPreview(_ value: ClipboardColorValue) -> some View {
        let swatch = Color(red: value.red, green: value.green, blue: value.blue, opacity: value.alpha)
        return VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(swatch)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                }
            HStack {
                Text(value.hex)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                Spacer()
                Text("RGB \(Int(round(value.red * 255))), \(Int(round(value.green * 255))), \(Int(round(value.blue * 255)))")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var imagePreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.055))
            if let thumbnail {
                Image(decorative: thumbnail, scale: 2)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(6)
            } else {
                VStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("加载缩略图…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
        }
    }

    private func linkPreview(accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let host = record.detectedURL?.host {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                    Text(host)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(accent.opacity(colorScheme == .dark ? 0.18 : 0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            Text(record.cardPreviewText ?? record.title)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .lineLimit(5)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func filesPreview(accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(record.fileURLs.prefix(3).enumerated()), id: \.offset) { _, url in
                HStack(spacing: 7) {
                    Image(systemName: fileSymbol(for: url))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(accent)
                        .frame(width: 22, height: 22)
                        .background(accent.opacity(colorScheme == .dark ? 0.18 : 0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text(url.lastPathComponent)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            if record.fileURLs.count > 3 {
                Text("还有 \(record.fileURLs.count - 3) 个文件…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 29)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func textPreview(isCode: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(record.cardPreviewText ?? record.title)
                .font(
                    isCode
                        ? .system(size: 11.5, design: .monospaced)
                        : .system(size: 12.5, weight: .regular)
                )
                .foregroundStyle(Color.primary.opacity(0.9))
                .lineSpacing(3.5)
                .lineLimit(record.isPreviewTruncated ? 6 : 7)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if record.isPreviewTruncated {
                Text("已节选预览 · 粘贴时保留全文")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
            }
        }
    }

    private var otherPreview: some View {
        VStack(spacing: 8) {
            Image(systemName: record.kind.symbolName)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text(record.title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fileSymbol(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "svg":
            return "photo"
        case "pdf":
            return "doc.richtext"
        case "zip", "tar", "gz", "dmg", "pkg":
            return "archivebox"
        case "swift", "ts", "js", "py", "go", "rs", "json", "md", "html", "css":
            return "doc.text"
        case "mp4", "mov", "mkv":
            return "film"
        case "mp3", "wav", "m4a":
            return "waveform"
        case "":
            return "folder"
        default:
            return "doc"
        }
    }
}
