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
- `-module <name>`: opens a module (`smartCare`, `cleanup`, `spaceLens`, ...)
- `-autoScan YES`: starts its scan right away
- `-AppleLanguages "(fr)"`: runs the app in French

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
