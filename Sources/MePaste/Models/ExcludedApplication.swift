import Foundation

struct ExcludedApplication: Codable, Identifiable, Equatable {
    let bundleIdentifier: String
    let name: String

    var id: String { bundleIdentifier }

    init(bundleIdentifier: String, name: String) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
    }

    init?(url: URL) {
        guard let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier, !identifier.isEmpty
        else { return nil }
        bundleIdentifier = identifier
        name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
    }
}
