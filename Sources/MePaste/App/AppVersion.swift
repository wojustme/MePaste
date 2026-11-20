import Foundation

enum AppVersion {
    // Packaging adds the release tag only for GitHub Releases. The embedded
    // commit also works with swift run and when a local binary leaves the repo.
    static let current = resolve(
        commitID: GeneratedBuildVersion.commitID,
        releaseVersion: Bundle.main.object(forInfoDictionaryKey: "MePasteReleaseVersion") as? String
    )

    static func resolve(commitID: String, releaseVersion: String?) -> String {
        if let version = releaseVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
           !version.isEmpty {
            return version
        }
        return "dev-\(commitID)"
    }
}
