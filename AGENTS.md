# Repository Guidelines

## Project Structure & Module Organization

MePaste is a native macOS Swift app built with Swift Package Manager. Source code lives under `Sources/MePaste/`:

- `App/` contains app lifecycle, shared state, windows, and the history panel controller.
- `Views/` contains SwiftUI and AppKit-backed UI components.
- `Models/` defines clipboard records, hot keys, and retention policy types.
- `Services/` contains clipboard monitoring, persistence, launch-at-login, and global hot key logic.
- `Resources/` stores `Info.plist` and app icon assets.
- `scripts/` contains packaging and release helpers.
- `docs/releases/` stores per-tag GitHub Release notes.

There is currently no dedicated test target.

## Build, Test, and Development Commands

- `swift build` builds the debug executable and catches compile errors.
- `swift run MePaste` builds and launches the local app.
- `swift package clean` clears SwiftPM build artifacts when module caches become stale.
- `./scripts/build-app.sh` creates a Universal 2 `.app` bundle in `build/`.
- `./scripts/build-dmg.sh` packages `build/MePaste.app` into `build/MePaste.dmg`.
- `./scripts/prepare-release.sh 0.0.x` builds release assets and SHA-256 files in `build/release/`.

If sandboxed tools cannot write Swift compiler caches, rerun the same build command with the required local permission rather than changing project paths.

## Coding Style & Naming Conventions

Use Swift 6 style with 4-space indentation. Keep UI code in `Views/`, app coordination in `App/`, and platform services in `Services/`. Prefer descriptive type names such as `HistoryPanelController`, `ClipboardMonitor`, and `RetentionPolicy`. Keep `@MainActor` on UI-facing model/controller types that mutate SwiftUI-observed state. Use small helper extensions for repeated platform checks or event handling rather than scattering magic numbers.

## Testing Guidelines

No automated tests are configured yet. For changes, run `swift build` at minimum. Manually verify user-facing behavior with `swift run MePaste`, especially global hot keys, clipboard writes, search, keyboard navigation, focus restoration, and settings persistence. If adding tests, create a SwiftPM test target and name tests by behavior, for example `testMoveSelectionSkipsOutsideFilteredRecords`.

## Commit & Pull Request Guidelines

History uses concise Conventional Commit-style messages: `fix: ...`, `feat: ...`, `chore: ...`, `ci: ...`, and `refactor: ...`. Keep commits scoped and user-visible when possible, for example `fix: restore focus after history panel dismissal`.

For PRs, include a short summary, validation steps, linked issues if any, and screenshots or screen recordings for UI changes. For releases, update `Resources/Info.plist`, add `docs/releases/vX.Y.Z.md`, create an annotated `vX.Y.Z` tag, and push it to trigger the Release workflow.
