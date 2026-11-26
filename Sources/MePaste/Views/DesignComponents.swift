import AppKit
import SwiftUI

struct KeyCapBadge: View {
    let text: String
    var prominent: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(prominent ? Color.accentColor : Color.primary.opacity(0.75))
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background {
                RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                    .fill(
                        prominent
                            ? Color.accentColor.opacity(colorScheme == .dark ? 0.22 : 0.14)
                            : Color.primary.opacity(colorScheme == .dark ? 0.11 : 0.065)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                    .strokeBorder(
                        prominent
                            ? Color.accentColor.opacity(0.45)
                            : Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.12),
                        lineWidth: 0.75
                    )
            }
    }
}

struct StatusPill: View {
    let title: String
    let tint: Color
    var symbol: String? = nil

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
            } else {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
            }
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 3.5)
        .background(tint.opacity(colorScheme == .dark ? 0.18 : 0.11))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .strokeBorder(tint.opacity(0.24), lineWidth: 0.75)
        }
    }
}

enum ClipboardVisualCategory {
    case text
    case code
    case link
    case color(ClipboardColorValue)
    case image
    case files
    case other

    init(record: ClipboardRecord) {
        switch record.kind {
        case .image:
            self = .image
        case .files:
            self = .files
        case .other:
            self = .other
        case .text:
            if let colorValue = record.detectedColor {
                self = .color(colorValue)
            } else if record.detectedURL != nil {
                self = .link
            } else if record.isCodeLike {
                self = .code
            } else {
                self = .text
            }
        }
    }

    var label: String {
        switch self {
        case .text: return "文本"
        case .code: return "代码"
        case .link: return "链接"
        case .color: return "颜色"
        case .image: return "图片"
        case .files: return "文件"
        case .other: return "剪贴板"
        }
    }

    var symbolName: String {
        switch self {
        case .text: return "text.alignleft"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .link: return "link"
        case .color: return "paintpalette.fill"
        case .image: return "photo.fill"
        case .files: return "folder.fill"
        case .other: return "clipboard.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .text: return Color(red: 0.23, green: 0.51, blue: 0.96)
        case .code: return Color(red: 0.39, green: 0.40, blue: 0.95)
        case .link: return Color(red: 0.06, green: 0.65, blue: 0.75)
        case .color(let value):
            return Color(red: value.red, green: value.green, blue: value.blue, opacity: max(value.alpha, 0.85))
        case .image: return Color(red: 0.68, green: 0.36, blue: 0.93)
        case .files: return Color(red: 0.92, green: 0.54, blue: 0.14)
        case .other: return Color(red: 0.47, green: 0.53, blue: 0.60)
        }
    }
}

enum RelativeTimeFormatter {
    private static let calendar = Calendar.current

    static func string(from date: Date, relativeTo now: Date) -> String {
        let interval = max(0, now.timeIntervalSince(date))
        if interval < 45 {
            return "刚刚"
        }
        let minutes = Int(interval / 60)
        if minutes < 60 {
            return "\(minutes) 分钟前"
        }
        let hours = Int(interval / 3_600)
        if hours < 24 {
            return "\(hours) 小时前"
        }
        if calendar.isDateInYesterday(date) {
            return "昨天"
        }
        let days = Int(interval / 86_400)
        if days < 30 {
            return "\(days) 天前"
        }
        let months = days / 30
        if months < 12 {
            return "\(months) 个月前"
        }
        return "\(days / 365) 年前"
    }
}

@MainActor
final class AppIconCache {
    static let shared = AppIconCache()
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 64
    }

    func icon(forBundleIdentifier bundleIdentifier: String) -> NSImage? {
        let key = bundleIdentifier as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 28, height: 28)
        cache.setObject(icon, forKey: key)
        return icon
    }
}
