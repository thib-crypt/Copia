# Copia

A fast, private clipboard history for macOS — native Swift/SwiftUI + AppKit, no dependencies, no network.
Lives in the menu bar and opens a floating panel at your text cursor (⌥⌘V).

**Requires** macOS 26 (Tahoe) · Apple Silicon. UI in French.

## Install
Download the latest `Copia-<version>.dmg` from [Releases](https://github.com/thib-crypt/Copia/releases), open it and drag
Copia to Applications. The app is signed with a Developer ID and notarized by Apple.
On first paste, macOS asks for the **Accessibility** permission (Copia sends ⌘V to the frontmost app).

## Features
- **Fuzzy search** over the whole history: accent- and case-insensitive, words in any order, typo-tolerant
  (Damerau-Levenshtein), highlighted matches.
- **Text, rich text, images and Finder files**: rich text pastes with its formatting (⌥↩ for plain text), images are stored
  as HEIC with thumbnails and **Vision OCR** (French + English) so screenshots are searchable, files paste back as files.
- **Dictation-aware dedup**: identical texts are merged; the A → B → A clipboard restore done by dictation apps
  (VoiceInk, superwhisper…) is detected through nspasteboard.org markers and timing, so it doesn't pollute the history.
- **Privacy**: respects `org.nspasteboard.ConcealedType` / `TransientType` (password managers), per-app exclusions,
  zero network access, no telemetry.
- **Keyboard first**: ↑↓, ↩ paste, ⌘↩ copy only, ⌘1…9, ⌘P pin, ⌘⌫ delete, ⌘Y preview, ⌘← ⌘→ filters, ⎋.
- **Retention**: up to 5,000 clips, by age (7/30/90/365 days), 1 GB disk cap for media; pinned clips are kept.
- **Import from CopyClip** (FIPLAB) history.
- **Forma integration**: shows the savings when [Forma](https://github.com/thib-crypt/Forma) optimizes a copied image,
  and links the optimized copy to the original.
- **Energy**: only `changeCount` is polled with an adaptive, tolerant timer; fully paused during sleep, display off or a
  locked session; the SwiftUI panel is torn down when closed.

Design notes and history: [docs/PLAN.md](docs/PLAN.md) (French).

## Updates
Copia updates itself with [Sparkle](https://sparkle-project.org): it checks
[`appcast.xml`](appcast.xml) once a day (and on demand from « Rechercher les mises à jour… »), downloads the new DMG from
GitHub Releases, verifies its EdDSA signature and Apple notarization, then replaces and relaunches the app.

## Build
Requirements: Xcode 26, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
The project signs with a Developer ID certificate (team `PG46BWSK3T`): change `DEVELOPMENT_TEAM` in `project.yml`
to build under your own account.
```
scripts/install.sh                      # xcodegen + Release build + install in /Applications + relaunch
xcodebuild test -scheme Copia -derivedDataPath build/DD
```

## Release
```
scripts/release.sh            # dist/Copia-<version>.dmg — hardened runtime, signed, notarized, stapled
scripts/release.sh --publish  # + tag v<version>, GitHub Release with the DMG, appcast.xml pushed (update goes live)
```
The version is `CFBundleShortVersionString` in `project.yml`. Only that version needs bumping: the build number Sparkle compares is the commit count.
Notarization uses the Keychain profile `notary`
(`xcrun notarytool store-credentials notary --apple-id <apple-id> --team-id PG46BWSK3T`, once); the update signature uses the Sparkle EdDSA key in the
Keychain (`generate_keys`, once — back it up with `generate_keys -x <file>`).

## License
[MIT](LICENSE)
