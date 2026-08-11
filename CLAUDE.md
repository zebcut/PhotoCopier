# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**PhotoCopier** — native macOS SwiftUI app that copies files from a memory card to a disk,
sorting them into a `YYYY/MM/DD` tree based on file creation date. Rewrite of an earlier
cross-platform Python/CustomTkinter tool (`Python/photo-organizer/` in the parent workspace),
built exclusively for macOS at the user's request.

Status: functional, manually tested end-to-end (business logic validated via standalone scripts
on temp files with forced timestamps; UI not screenshot-tested — no screen-recording/accessibility
permission in the agent sandbox that built it).

## Environment constraint

Only Xcode Command Line Tools are installed, not full Xcode (`xcode-select -p` →
`/Library/Developer/CommandLineTools`, no `xcodebuild`). The project is therefore a plain
**Swift Package Manager** executable (`Package.swift`, no `.xcodeproj`), built/run via
`swift build` / `swift run`. Not sandboxed, not code-signed with a Developer ID — `NSOpenPanel`
file access works without security-scoped bookmarks. `Scripts/build_app.sh` assembles a real
`.app` bundle (Contents/MacOS + Info.plist) and ad-hoc signs it for local double-click use.

## Architecture

```
Sources/PhotoCopier/
├── PhotoCopierApp.swift        # @main entry point
├── ContentView.swift            # SwiftUI UI: sidebar (source/dest/extension checkboxes) + log/progress
├── OrganizerViewModel.swift     # @MainActor ObservableObject: scan, filter, start/cancel orchestration
└── Organizer.swift              # pure Foundation + CryptoKit logic, no UI dependency
```

`Organizer` is a generic type name (not tied to the project name) — do not rename it to
`PhotoCopier*` without an explicit request.

## Key functional decisions (acted on, don't second-guess without asking)

- Fixed `YYYY/MM/DD` tree only — no alternate formats (the Python version has several; this v1
  deliberately doesn't, per explicit user scope choice)
- Date source priority, `Organizer.resolvedDate(of:)`: embedded capture metadata first
  (`Organizer.capturedDate(of:)` — EXIF `DateTimeOriginal`/`DateTimeDigitized`/TIFF `DateTime` via
  ImageIO for photos, QuickTime/MP4 `creationDate` via `AVURLAsset.load(.creationDate)` for
  `videoExtensions`), falling back to `Organizer.creationDate(of:)` (filesystem `creationDate` →
  `contentModificationDate`) when no metadata is embedded. **Do not revert to filesystem-date-only**:
  real-world bug hit 2026-08-11 — a camera JPG's filesystem birthtime didn't match its EXIF date
  (off by about a week, `2026/06/06` vs the correct `2026/05/30`) because the file had been
  recopied/reformatted on the card before reaching PhotoCopier's source folder; EXIF stayed
  correct because it's baked in at shooting time. `Organizer.organize` is `async` because of the
  `AVURLAsset` metadata load.
- All files copied recursively by default; after picking the source, the app scans it in the
  background and shows one checkbox per detected extension (all checked by default) — only
  checked extensions are copied
- Copy only, no move option (not requested for v1)
- Same-name collision at destination → SHA-256 checksum compare (`Organizer.checksum(of:)`,
  via CryptoKit, `Data(contentsOf:options:.mappedIfSafe)` to avoid fully loading large video
  files into memory): identical → skipped; different → copied with a numeric suffix
  (`Organizer.uniquePath`, `_1`, `_2`…)
- Undeterminable date (both `creationDate` and `contentModificationDate` unreadable — rare in
  practice; verified even a broken symlink still reports its own dates, not nil) → file goes
  into `<destination>/dateUnknown/` flat, not into the year/month/day tree
- Simple single-window UI, no menu-bar/background auto-launch-on-card-insert mode

## Testing

No automated test target. Business logic in `Organizer.swift` is pure Foundation/CryptoKit with
no UI dependency, so it can be exercised without the app: copy the file into a scratch dir, append
a small driver that calls `Organizer.scanFiles` / `Organizer.organize` on temp fixtures (use
`touch -t YYYYMMDDhhmm` to force creation dates on APFS), run with `swift <file>.swift`. This is
how skip/rename/dateUnknown behavior was verified during development — there's no `Package.swift`
test target to run instead.

## Git workflow

- Work on feature/dev branches, not directly on `main`, for anything beyond small fixes.
- **Never run `git push` without an explicit request from the user each time** — local edits and
  local commits are fine, pushing to `github.com/zebcut/PhotoCopier` is not, until asked.
