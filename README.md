<p align="center">
  <img src="App/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png" width="128" alt="Lucent icon">
</p>

<h1 align="center">Lucent</h1>

<p align="center">
  A free and open source Mac cleaner and care app, built natively in SwiftUI.<br>
  <a href="README.fr.md">Version française</a>
</p>

---

Lucent keeps your Mac clean, safe and fast, with a polished interface and no subscription. Tools like this are useful to everyone, so they should be free for everyone.

> **Status: early preview (0.1).** Smart Care, Cleanup, Space Lens and My Activity work today. The other modules are built in the open; see the [roadmap](#roadmap).

## Features

| Module | What it does | Status |
|---|---|---|
| **Smart Care** | One-click checkup: finds junk, checks the Mac's built-in protections (SIP, Gatekeeper, FileVault, firewall), measures free space and gives a health score | ✅ 0.1 |
| **Cleanup** | System junk (caches, logs, Xcode, browsers, package managers), AI clutter (AI app caches, ML package caches, downloaded models), Mail attachments, Trash bins | ✅ 0.1 |
| **Space Lens** | Navigable bubble map of any folder or the whole disk; remove what you don't need | ✅ 0.1 |
| **My Activity** | History of everything that was cleaned | ✅ 0.1 |
| **Applications** | Complete uninstaller, leftovers finder, app updates (Sparkle, App Store, Homebrew) | 🛠 0.2 |
| **Performance** | Maintenance tasks, login items, background items | 🛠 0.2 |
| **Protection** | Malware scan with Apple's XProtect YARA rules, persistence check, privacy cleanup, app permissions | 🛠 0.3 |
| **My Clutter** | Duplicates, similar photos, large and old files | 🛠 0.3 |
| **Menu bar** | Live CPU, memory, disk, network and battery stats | 🛠 0.3 |
| **Cloud Cleanup** | Large files and local copies of iCloud Drive, Google Drive, OneDrive | 🛠 0.4 |

## Safety first

A cleaner touches your files, so Lucent is careful by design:

- **Nothing is deleted without a review.** Every scan ends on a summary you can inspect item by item.
- **Everything goes to the Trash**, except what is already in a Trash when you choose to empty it.
- **A safety guard** checks every single item right before it is touched. It refuses system locations, your documents (for automatic cleanups), keychains, iCloud and cloud storage folders, Mail and Messages databases, and the caches macOS cannot rebuild safely. Symbolic links are resolved first, so a link cannot trick it.
- **Apps that are running** keep their caches: those items start unchecked.
- **Simulation mode** (Settings) runs every flow without deleting anything.
- **Exclusions**: tell Lucent which folders it must never touch.
- **No network, no telemetry.** Lucent never sends anything off your Mac.

## Requirements

- macOS 14 Sonoma or later (Liquid Glass effects on macOS 26 and later)
- Apple silicon or Intel

## Build from source

```bash
brew install xcodegen
git clone https://github.com/mbielle/lucent.git
cd lucent
xcodegen generate
open Lucent.xcodeproj
```

Then press ⌘R in Xcode. Or from the terminal:

```bash
xcodebuild -project Lucent.xcodeproj -scheme Lucent -configuration Release -derivedDataPath build build
open build/Build/Products/Release/Lucent.app
```

For the best results, give Lucent **Full Disk Access** (System Settings › Privacy & Security). The app walks you through it.

## Project layout

```
App/                    SwiftUI app: design system, modules, onboarding, settings
Packages/LucentKit/     Engine, testable without UI
  Sources/LucentKit/
    Core/               SafetyGuard, Remover, ActivityLog, models
    Rules/              Rule model + glob expansion
    Resources/Rules/    Cleanup rules as JSON (add yours here!)
    Cleanup/            CleanupScanner
    SpaceLens/          SpaceScanner (folder tree)
    System/             Security checks, disk info, Full Disk Access
  Tests/                Swift Testing suite on throwaway fake home folders
project.yml             XcodeGen spec (the .xcodeproj is generated)
```

### Adding a cleanup rule

Rules are plain JSON in `Packages/LucentKit/Sources/LucentKit/Resources/Rules/`. Example:

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

Then run `swift test` in `Packages/LucentKit`: the suite checks that every rule only reaches locations the safety guard allows.

## Roadmap

- **0.2**: privileged helper (SMAppService), Applications (uninstaller, leftovers, updater), Performance
- **0.3**: Protection (XProtect YARA scan, persistence, privacy, permissions), My Clutter, menu bar monitor, My Tools
- **0.4**: Cloud Cleanup, scheduled scans, signed and notarized DMG, Homebrew cask

## Contributing

Contributions are welcome, especially new cleanup rules and translations. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Lucent is free software, licensed under the [GNU General Public License v3.0](LICENSE). Credits for the open source projects it learns from are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Lucent is an independent project. It is not affiliated with MacPaw or CleanMyMac.
