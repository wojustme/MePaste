import SwiftUI

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
        HStack {
            Label("MePaste", systemImage: "clipboard.fill")
                .font(.headline)
            Text("\(model.records.count) 条记录")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("点击或使用 ← →，按 Return 复制")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
    }

    @ViewBuilder
    private var content: some View {
        if model.records.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "clipboard")
                    .font(.system(size: 38))
                    .foregroundStyle(.secondary)
                Text("暂无剪贴板历史")
                    .font(.headline)
                Text("复制文本、图片或文件后，记录会显示在这里")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14) {
                        ForEach(model.records) { record in
                            ClipboardCard(
                                record: record,
                                isSelected: model.selectedRecordID == record.id,
                                onSelect: { model.select(record) },
                                onDelete: { model.delete(record) }
                            )
                            .id(record.id)
                            .onTapGesture {
                                model.selectedRecordID = record.id
                                model.select(record)
                            }
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

    private var footer: some View {
        HStack(spacing: 16) {
            Label(model.hotKey.displayName, systemImage: "command")
            Spacer()
            Label("文本", systemImage: "text.alignleft")
            Label("图片", systemImage: "photo")
            Label("文件及富文本", systemImage: "doc.on.doc")
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
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(record.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            HStack {
                Label(record.subtitle, systemImage: record.kind.symbolName)
                    .lineLimit(1)
                Spacer()
                Text(record.createdAt, style: .relative)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 210, height: 205)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? Color.accentColor : .white.opacity(0.12), lineWidth: 2)
        }
        .contextMenu {
            Button("复制到剪贴板", action: onSelect)
            Divider()
            Button("删除", role: .destructive, action: onDelete)
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let image = record.image {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if let text = record.plainText {
            ScrollView {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.disabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else if !record.fileURLs.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 38))
                Text(record.fileURLs.map(\.lastPathComponent).joined(separator: "\n"))
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
