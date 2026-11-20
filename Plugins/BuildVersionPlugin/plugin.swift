import Foundation
import PackagePlugin

@main
struct BuildVersionPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: any Target) async throws -> [Command] {
        let outputDirectory = context.pluginWorkDirectoryURL.appendingPathComponent("BuildVersion")
        let script = context.package.directoryURL.appendingPathComponent("scripts/generate-build-version.sh")

        // Run before every build so changing HEAD also updates incremental builds.
        // The script leaves the output untouched when the commit has not changed.
        return [
            .prebuildCommand(
                displayName: "Generate MePaste build version",
                executable: URL(fileURLWithPath: "/bin/bash"),
                arguments: [script.path, context.package.directoryURL.path, outputDirectory.path],
                outputFilesDirectory: outputDirectory
            )
        ]
    }
}
