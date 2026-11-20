import Foundation
import Testing
@testable import MePaste

struct AppVersionTests {
    @Test func testLocalBuildDisplaysEmbeddedCommit() {
        #expect(AppVersion.resolve(commitID: "abc1234", releaseVersion: nil) == "dev-abc1234")
        #expect(AppVersion.current == "dev-\(GeneratedBuildVersion.commitID)")
    }

    @Test func testReleaseDisplaysExactTagInsteadOfCommit() {
        #expect(AppVersion.resolve(commitID: "abc1234", releaseVersion: "v1.2.3") == "v1.2.3")
    }

    @Test func testEmptyReleaseMetadataDoesNotHideDevelopmentVersion() {
        #expect(AppVersion.resolve(commitID: "abc1234", releaseVersion: " \n ") == "dev-abc1234")
    }

    @Test func testSourceArchiveWithoutGitIsExplicitlyUnknown() {
        #expect(AppVersion.resolve(commitID: "unknown", releaseVersion: nil) == "dev-unknown")
    }
}

struct BuildVersionScriptTests {
    @Test func testLocalPackagingIsDevelopmentEvenOnATag() throws {
        let fixture = try VersionScriptFixture()
        defer { fixture.cleanUp() }
        let result = try fixture.releaseVersion(actions: "false", refType: "tag", refName: "v1.2.3")
        #expect(result.status == 0)
        #expect(result.output.isEmpty)
    }

    @Test func testNonTagCIBuildIsDevelopment() throws {
        let fixture = try VersionScriptFixture()
        defer { fixture.cleanUp() }
        let result = try fixture.releaseVersion(actions: "true", refType: "branch", refName: "main")
        #expect(result.status == 0)
        #expect(result.output.isEmpty)
    }

    @Test func testGitHubReleaseUsesTagMatchingBundleVersion() throws {
        let fixture = try VersionScriptFixture()
        defer { fixture.cleanUp() }
        let result = try fixture.releaseVersion(actions: "true", refType: "tag", refName: "v1.2.3")
        #expect(result.status == 0)
        #expect(result.output == "v1.2.3")
    }

    @Test(arguments: ["v9.9.9", "", "1.2.3"])
    func testMismatchedOrMissingReleaseTagFailsBeforePackaging(tag: String) throws {
        let fixture = try VersionScriptFixture()
        defer { fixture.cleanUp() }
        let result = try fixture.releaseVersion(actions: "true", refType: "tag", refName: tag)
        #expect(result.status != 0)
        #expect(result.output.contains("must match app version"))
    }

    @Test func testGeneratorRefreshesCommitWithoutRewritingUnchangedOutput() throws {
        let fixture = try VersionScriptFixture()
        defer { fixture.cleanUp() }
        #expect(try fixture.git(["init", "--quiet", "--initial-branch=codex/version-test"]).status == 0)
        #expect(try fixture.commit("first").status == 0)
        let firstCommit = try fixture.git(["rev-parse", "--short=7", "HEAD"]).output
        #expect(try fixture.generate().status == 0)
        #expect(try String(contentsOf: fixture.generatedFile, encoding: .utf8).contains("\"\(firstCommit)\""))

        let sentinelDate = Date(timeIntervalSince1970: 1_000_000_000)
        try FileManager.default.setAttributes([.modificationDate: sentinelDate], ofItemAtPath: fixture.generatedFile.path)
        #expect(try fixture.generate().status == 0)
        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.generatedFile.path)
        #expect(attributes[.modificationDate] as? Date == sentinelDate)

        #expect(try fixture.commit("second").status == 0)
        let secondCommit = try fixture.git(["rev-parse", "--short=7", "HEAD"]).output
        #expect(firstCommit != secondCommit)
        #expect(try fixture.generate().status == 0)
        let updated = try String(contentsOf: fixture.generatedFile, encoding: .utf8)
        #expect(updated.contains("\"\(secondCommit)\""))
        #expect(!updated.contains("\"\(firstCommit)\""))
    }

    @Test func testGeneratorHandlesArchiveWithoutGitMetadata() throws {
        let fixture = try VersionScriptFixture()
        defer { fixture.cleanUp() }
        #expect(try fixture.generate().status == 0)
        #expect(try String(contentsOf: fixture.generatedFile, encoding: .utf8).contains("\"unknown\""))
    }
}

private struct ScriptResult {
    let status: Int32
    let output: String
}

private struct VersionScriptFixture {
    private static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    let directory: URL
    private let infoPlist: URL
    private let generatedDirectory: URL
    var generatedFile: URL { generatedDirectory.appendingPathComponent("GeneratedBuildVersion.swift") }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        infoPlist = directory.appendingPathComponent("Info.plist")
        generatedDirectory = directory.appendingPathComponent("Generated")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleShortVersionString": "1.2.3"],
            format: .xml,
            options: 0
        )
        try data.write(to: infoPlist)
    }

    func releaseVersion(actions: String, refType: String, refName: String) throws -> ScriptResult {
        try run("/bin/bash", [script("release-version.sh"), infoPlist.path], environment: [
            "GITHUB_ACTIONS": actions,
            "GITHUB_REF_TYPE": refType,
            "GITHUB_REF_NAME": refName
        ])
    }

    func generate() throws -> ScriptResult {
        try run("/bin/bash", [script("generate-build-version.sh"), directory.path, generatedDirectory.path])
    }

    func git(_ arguments: [String]) throws -> ScriptResult {
        try run("/usr/bin/git", ["-C", directory.path] + arguments)
    }

    func commit(_ message: String) throws -> ScriptResult {
        try git([
            "-c", "user.name=MePaste Tests",
            "-c", "user.email=tests@example.invalid",
            "-c", "commit.gpgsign=false",
            "-c", "core.hooksPath=/dev/null",
            "commit", "--quiet", "--allow-empty", "-m", message
        ])
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func script(_ name: String) -> String {
        Self.repository.appendingPathComponent("scripts/\(name)").path
    }

    private func run(
        _ executable: String,
        _ arguments: [String],
        environment: [String: String] = [:]
    ) throws -> ScriptResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        var isolatedEnvironment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
        isolatedEnvironment["GIT_CONFIG_GLOBAL"] = "/dev/null"
        isolatedEnvironment["GIT_CONFIG_SYSTEM"] = "/dev/null"
        isolatedEnvironment.merge(environment) { _, new in new }
        process.environment = isolatedEnvironment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ScriptResult(
            status: process.terminationStatus,
            output: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
