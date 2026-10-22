# Contributing to Lucent

Thanks for helping! Lucent touches people's files, so safety comes before features.

## Getting started

```bash
brew install xcodegen
xcodegen generate
open Lucent.xcodeproj
```

- The `.xcodeproj` is generated: edit `project.yml`, never the project file.
- Engine code lives in `Packages/LucentKit` and must be covered by tests: `cd Packages/LucentKit && swift test`.
- Tests run on throwaway fake home folders. Never write a test that touches the real home folder, except opt-in ones guarded by an environment variable.

## Debug helpers

Debug builds accept launch arguments:

```bash
open build/DerivedData/Build/Products/Debug/Lucent.app --args -dryRun YES -module cleanup -autoScan YES
```

- `-dryRun YES`: simulation mode, nothing is deleted
- `-home <path>`: scans this folder instead of your home (make one with `swift scripts/make-demo-home.swift <path>`)
- `-module <name>`: opens a module (`smartCare`, `cleanup`, `protection`, `performance`, `applications`, `myClutter`, `spaceLens`, `cloudCleanup`, `myTools`, `myActivity`)
- `-autoScan YES`: starts its scan right away
- `-section <name>`: then opens a detail screen (e.g. `uninstaller`, `updater`, `malware`, `similar`, `maintenance`)
- `-previewMenuBar YES`: shows the menu bar panel in a window
- `-AppleLanguages "(fr)"`: runs the app in French

Without Full Disk Access, macOS asks for permission (and blocks) the first time Lucent opens Desktop,
Documents or Downloads. Use `-home` with the demo folder to test without those prompts.

## Real removal tests

Two opt-in tests move a tiny probe file to your real Trash to check the end-to-end path:

```bash
cd Packages/LucentKit && LUCENT_TRASH_TEST=1 swift test --filter "RealTrash|RealWorkspace"
```

## Cleanup rules

1. Add the rule to the JSON file of its category in `Packages/LucentKit/Sources/LucentKit/Resources/Rules/`.
2. Explain in `detail` what the files are and what happens after removal.
3. If removing the data costs the user anything (re-downloads, lost settings), set `"selectedByDefault": false`.
4. List the app's bundle ids in `appBundleIDs` so its items stay unchecked while it runs.
5. Run `swift test`.

## Translations

UI strings live in `App/Resources/Localizable.xcstrings` (edit it in Xcode). Rule texts carry their translations in the JSON files.

## Pull requests

- One topic per pull request, with a short description of what changed and how you tested it.
- Code must build with Swift 6 strict concurrency and no warnings.
