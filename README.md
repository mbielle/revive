<p align="center">
  <img src="App/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png" width="128" alt="Revive icon">
</p>

<h1 align="center">Revive</h1>

<p align="center">
  A free and open source Mac cleaner, optimizer and malware scanner, built natively in SwiftUI.<br>
  <a href="README.fr.md">Version française</a>
</p>

---

Revive keeps your Mac clean, safe and fast, with a polished interface and no subscription. Tools like this are useful to everyone, so they should be free for everyone.

> **Status: preview (0.4).** Every module works. It has not yet been tested widely: keep **Simulation mode** on (Settings) until you trust it, and report anything odd.

## Features

| Module | What it does |
|---|---|
| **Checkup** | One click: junk, built-in protections (SIP, Gatekeeper, FileVault, firewall), malware quick scan, memory and app updates, with a health score and one Run button |
| **Cleanup** | System junk (caches, logs, Xcode, browsers, package managers), AI clutter (AI app caches, ML package caches, downloaded models), Mail attachments, Trash bins |
| **Security** | Malware scan with **Apple's own XProtect signatures** (YARA), suspicious startup items, browser history and cookies, browser extensions, saved Wi-Fi networks, app permissions (camera, microphone, screen, files…) |
| **Optimization** | Maintenance tasks (free RAM, flush DNS, repair "Open With", reset Quick Look, reindex Spotlight, thin Time Machine snapshots), login items, background agents and daemons, heavy CPU and memory consumers |
| **Apps** | Complete uninstaller with leftover review and app reset, files of apps already deleted, installer files, updates from Sparkle feeds, the Mac App Store and Homebrew |
| **Declutter** | Duplicates (SHA-256), similar photos (Apple Vision), large and old files, screenshots |
| **Storage Map** | Navigable bubble map of any folder or of the whole disk |
| **Cloud Storage** | iCloud Drive, Google Drive, OneDrive, Dropbox: free local copies without deleting anything from the cloud, find local duplicates of cloud files |
| **Shortcuts** | Pin your favorite tools |
| **History** | History of everything that was removed |
| **Menu bar** | Live CPU, memory, disk, battery and network, one-click RAM release |
| **Automatic scans** | Daily or weekly junk check that only notifies you |

English and French.

## Safety first

A cleaner touches your files, so Revive is careful by design:

- **Nothing is removed without a review.** Every scan ends on a summary you can inspect item by item.
- **Everything goes to the Trash**, except what is already in a Trash when you choose to empty it.
- **A safety guard** checks every item right before it is touched. It refuses system locations, your documents for automatic cleanups, keychains, iCloud and cloud storage folders, Mail and Messages databases, Apple's own apps and data, and the caches macOS cannot rebuild safely. Symbolic links are resolved first.
- **Running apps** keep their caches: those items start unchecked. Apps are quit before being uninstalled.
- **Uninstalling is strict**: only files named exactly after the app's bundle identifier or name are proposed.
- **Simulation mode** runs every flow without changing anything. **Exclusions** protect the folders you choose.
- **Your data stays on your Mac.** The only network requests are update checks (each app's own update feed, Apple's App Store lookup), made when you open the Updater or run Checkup.

## How it works

| Need | Approach |
|---|---|
| Malware signatures | Apple ships its XProtect YARA rules on every Mac and keeps them up to date. Revive compiles them with a vendored [YARA](https://github.com/VirusTotal/yara) 4.5.4 and scans startup programs, apps, Downloads and Desktop (deep scan: more folders) |
| Administrator tasks | A small privileged helper (SMAppService launch daemon, XPC) runs a closed list of commands, only for a Revive app signed by the same team. Unsigned builds can't prove who is calling, so their helper refuses every connection and macOS asks for your password instead |
| Junk rules | Declarative JSON files: adding a rule needs no Swift code |
| Similar photos | Apple Vision feature prints compared between neighboring shots |

## Requirements

- macOS 14 Sonoma or later (Liquid Glass effects on macOS 26 and later)
- Apple silicon or Intel

## Install

Download the latest DMG from [Releases](https://github.com/mbielle/revive/releases), open it and drag Revive to Applications. Then give Revive **Full Disk Access** when it asks (System Settings › Privacy & Security): without it, macOS hides Mail, Safari, the Trash and app data.

## Build from source

```bash
brew install xcodegen
git clone https://github.com/mbielle/revive.git
cd revive
xcodegen generate
open Revive.xcodeproj
```

Press ⌘R. To package a DMG: `scripts/make-dmg.sh` (see the script for signing and notarization).

### Try it on fake data

```bash
swift scripts/make-demo-home.swift /tmp/ReviveDemo
open build/DerivedData/Build/Products/Debug/Revive.app --args -home /tmp/ReviveDemo -dryRun YES
```

Debug builds then scan a generated folder full of junk, duplicates, similar photos, a fake cloud drive and a suspicious startup item, instead of your home folder.

## Project layout

```
App/                      SwiftUI app: design system, one folder per module, menu bar, settings
Helper/                   Privileged helper (launch daemon) and its launchd plist
Packages/ReviveKit/       Engine, testable without UI
  Sources/ReviveKit/
    Core/                 SafetyGuard, Remover, WorkspaceRemover, ActivityLog
    Rules/ Resources/     Cleanup rules (JSON) and their glob engine
    Cleanup/ SpaceLens/ Apps/ Performance/ Protection/ Clutter/ Cloud/ System/ Privileged/
  Sources/CYara/          Vendored libyara (BSD-3-Clause)
  Tests/                  Swift Testing suite on throwaway fake home folders
scripts/                  Demo home generator, DMG packaging
Casks/                    Homebrew cask template
project.yml               XcodeGen spec (the .xcodeproj is generated)
```

### Adding a cleanup rule

Rules live in `Packages/ReviveKit/Sources/ReviveKit/Resources/Rules/`:

```json
{
  "id": "my-app-cache",
  "category": "systemJunk",
  "symbol": "archivebox",
  "title": { "en": "My App Cache", "fr": "Cache de My App" },
  "detail": { "en": "What it is and why it is safe to remove.", "fr": "…" },
  "paths": ["~/Library/Application Support/MyApp/Cache"],
  "appBundleIDs": ["com.example.myapp"],
  "selectedByDefault": true
}
```

Then run `swift test` in `Packages/ReviveKit`: the suite checks that every rule only reaches locations the safety guard allows.

## Contributing

Contributions are welcome, especially cleanup rules and translations. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Revive is free software, licensed under the [GNU General Public License v3.0](LICENSE). Credits are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Revive is an independent project, not affiliated with MacPaw or CleanMyMac.
