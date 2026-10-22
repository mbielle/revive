# Contributing to Revive

Thanks for helping! Revive touches people's files, so safety comes before features.

## Getting started

```bash
brew install xcodegen
xcodegen generate
open Revive.xcodeproj
```

- The `.xcodeproj` is generated: edit `project.yml`, never the project file.
- Engine code lives in `Packages/ReviveKit` and must be covered by tests: `cd Packages/ReviveKit && swift test`.
- Tests run on throwaway fake home folders. Never write a test that touches the real home folder, except opt-in ones guarded by an environment variable.

## Debug helpers

Debug builds accept launch arguments:

```bash
open build/DerivedData/Build/Products/Debug/Revive.app --args -dryRun YES -module cleanup -autoScan YES
```

- `-dryRun YES`: simulation mode, nothing is deleted
- `-home <path>`: scans this folder instead of your home (make one with `swift scripts/make-demo-home.swift <path>`)
- `-module <name>`: opens a module (`smartCare`, `cleanup`, `protection`, `performance`, `applications`, `myClutter`, `spaceLens`, `cloudCleanup`, `myTools`, `myActivity`)
- `-autoScan YES`: starts its scan right away
- `-section <name>`: then opens a detail screen (e.g. `uninstaller`, `updater`, `malware`, `similar`, `maintenance`)
- `-previewMenuBar YES`: shows the menu bar panel in a window
- `-AppleLanguages "(fr)"`: runs the app in French

Without Full Disk Access, macOS asks for permission (and blocks) the first time Revive opens Desktop,
Documents or Downloads. Use `-home` with the demo folder to test without those prompts.

## Real removal tests

Three opt-in tests move a tiny probe file to your real Trash to check the end-to-end path:

```bash
cd Packages/ReviveKit && REVIVE_TRASH_TEST=1 swift test --filter "RealTrash|RealWorkspace|Osascript"
```

## Testing the privileged helper without root

The real helper can run in your user launchd domain (no administrator rights) to check launchd,
XPC and the code signature check with the Debug app:

```bash
APP="$PWD/build/DerivedData/Build/Products/Debug/Revive.app"
cat > /tmp/helper-selftest.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>io.github.mbielle.Revive.Helper.selftest</string>
<key>Program</key><string>$APP/Contents/MacOS/ReviveHelper</string>
<key>MachServices</key><dict><key>io.github.mbielle.Revive.Helper</key><true/></dict>
</dict></plist>
PLIST
launchctl bootstrap gui/$(id -u) /tmp/helper-selftest.plist
"$APP/Contents/MacOS/Revive" -dryRun YES -helperSelfTest YES   # look for HELPER-SELFTEST lines
launchctl bootout gui/$(id -u)/io.github.mbielle.Revive.Helper.selftest
```

Commands that need root fail with "Operation not permitted"; dangerous ones are refused with exit -2.
Installing the real daemon needs a build signed with a Developer ID (see `scripts/make-dmg.sh`).

## Cleanup rules

1. Add the rule to the JSON file of its category in `Packages/ReviveKit/Sources/ReviveKit/Resources/Rules/`.
2. Explain in `detail` what the files are and what happens after removal.
3. If removing the data costs the user anything (re-downloads, lost settings), set `"selectedByDefault": false`.
4. List the app's bundle ids in `appBundleIDs` so its items stay unchecked while it runs.
5. Run `swift test`.

## Translations

UI strings live in `App/Resources/Localizable.xcstrings` (edit it in Xcode). Rule texts carry their translations in the JSON files.

## Pull requests

- One topic per pull request, with a short description of what changed and how you tested it.
- Code must build with Swift 6 strict concurrency and no warnings.
