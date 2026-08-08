# Code Submission and Release Process

This document records the repository workflow used to commit code, push `main`, create a version tag, and publish a GitHub Release.

## 1. Review Current Changes

Start from the repository root and inspect the working tree before staging anything.

```bash
git status --short --branch
git diff --stat
git diff --
```

Confirm the diff belongs to the intended release. If there are unrelated files, stage only the files that are part of the release.

## 2. Update Version and Release Notes

For a new version such as `v0.0.4`, update:

- `Resources/Info.plist`
  - `CFBundleShortVersionString`: `0.0.4`
  - `CFBundleVersion`: `4`
- `docs/releases/v0.0.4.md`
  - Include short user-facing notes.
  - Mention fixes, improvements, and any behavior changes.

The GitHub Actions release workflow reads `docs/releases/${tag}.md` and uses it as the Release body.

## 3. Validate Locally

Run a build before committing:

```bash
swift build
```

If SwiftPM reports stale module cache paths, run:

```bash
swift package clean
swift build
```

For GUI behavior changes, also launch and manually verify:

```bash
swift run MePaste
```

## 4. Stage and Commit

Stage explicit files only:

```bash
git add Resources/Info.plist \
  Sources/MePaste/App/AppModel.swift \
  Sources/MePaste/App/HistoryPanelController.swift \
  docs/releases/v0.0.4.md
```

Use concise Conventional Commit-style messages:

```bash
git commit -m "fix: restore focus after history panel dismissal"
```

Common prefixes in this repository include `fix:`, `feat:`, `chore:`, `ci:`, and `refactor:`.

## 5. Sync, Push, and Tag

Fetch tags first to avoid duplicating a remote tag:

```bash
git fetch origin --tags
git tag --list
git push origin main
```

Create an annotated tag matching the app version:

```bash
git tag -a v0.0.4 -m "MePaste v0.0.4"
git push origin v0.0.4
```

Pushing the tag triggers `.github/workflows/release.yml`.

## 6. Verify GitHub Release

Check that the Release workflow completed successfully:

```bash
curl -sS 'https://api.github.com/repos/wojustme/MePaste/actions/runs?per_page=5'
```

Then verify the release and uploaded assets:

```bash
curl -sS 'https://api.github.com/repos/wojustme/MePaste/releases/tags/v0.0.4'
```

A successful release should include:

- `MePaste-v0.0.4.dmg`
- `MePaste-v0.0.4.dmg.sha256`
- Release body copied from `docs/releases/v0.0.4.md`

## 7. Final Sanity Check

Confirm the local branch is clean and aligned with the remote:

```bash
git status --short --branch
git log --oneline --decorate -4
git tag -n --list v0.0.4
```

Expected result: `main` matches `origin/main`, the release tag points at `HEAD`, and the working tree has no unintended changes.
