<p align="center">
  <img src="docs/icon.png" width="140" alt="Revive icon">
</p>

<h1 align="center">Revive</h1>

<p align="center">
  <strong>Bring your Mac back to life.</strong><br>
  A free and open source Mac cleaner, optimizer and malware scanner, built natively in SwiftUI.
</p>

<p align="center">
  <strong>English</strong> · <a href="README.fr.md">Français</a>
</p>

<p align="center">
  <a href="https://github.com/mbielle/revive/releases/latest"><img src="https://img.shields.io/github/v/release/mbielle/revive?include_prereleases&style=flat-square&color=7c3aed&label=release" alt="Latest release"></a>
  <a href="https://github.com/mbielle/revive/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/mbielle/revive/ci.yml?style=flat-square&label=CI" alt="CI status"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-111111?style=flat-square&logo=apple&logoColor=white" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/tests-59%20passing-22c55e?style=flat-square" alt="59 tests passing">
  <img src="https://img.shields.io/badge/telemetry-none-22c55e?style=flat-square" alt="No telemetry">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-2563eb?style=flat-square" alt="GPL-3.0"></a>
  <img src="https://img.shields.io/badge/PRs-welcome-ec4899?style=flat-square" alt="PRs welcome">
</p>

<p align="center">
  <img src="docs/screenshots/checkup.png" width="820" alt="Revive Checkup: health score, junk, security, optimization and app updates in one screen">
</p>

<p align="center">
  <a href="https://github.com/mbielle/revive/releases/latest"><img src="https://img.shields.io/badge/Download_for_macOS-000000?style=for-the-badge&logo=apple&logoColor=white" alt="Download for macOS" height="40"></a>
</p>

<p align="center">
  <sub>Free forever · No account · No subscription · Your files never leave your Mac</sub>
</p>

---

## Why Revive?

Keeping a Mac clean, safe and fast is useful to everyone, so the tool to do it should be free for everyone.

- 🆓 **Free and open source.** No subscription, no "Pro" tier, no nag screens. Every line of code is here, under the GPL-3.0.
- 🔒 **Private by design.** No analytics, no account, no server. The only network requests are update checks you start yourself.
- 🛡️ **Safe first.** Every scan ends on a review screen, everything goes to the Trash, and a safety guard re-checks each item right before it is touched.
- 🍎 **Truly native.** SwiftUI, Swift 6 strict concurrency, Apple's own frameworks (Vision, Security, ServiceManagement). Liquid Glass on macOS 26.
- 🧠 **Uses what your Mac already knows.** Malware detection runs on Apple's own XProtect signatures, already installed and kept up to date by macOS.

---

## Features at a glance

<table>
<tr>
<td width="33%" valign="top">

### 💜 Checkup
One scan for junk, security, speed and app updates, a health score, and one **Run** button to fix it all.

</td>
<td width="33%" valign="top">

### 🧹 Cleanup
System junk, AI caches and models, Mail attachments and Trash bins, with 30+ declarative rules.

</td>
<td width="33%" valign="top">

### 🛡️ Security
Malware scan with Apple's XProtect YARA rules, risky startup items, browser privacy, extensions, Wi-Fi, app permissions.

</td>
</tr>
<tr>
<td width="33%" valign="top">

### ⚡ Optimization
Maintenance scripts, login and background items, live CPU and memory consumers.

</td>
<td width="33%" valign="top">

### 📦 Apps
Complete uninstaller, app reset, leftovers of deleted apps, installers, updates from Sparkle, the App Store and Homebrew.

</td>
<td width="33%" valign="top">

### 🗂️ Declutter
Duplicates, similar photos (on-device Vision), large and old files, screenshots.

</td>
</tr>
<tr>
<td width="33%" valign="top">

### 🫧 Storage Map
An animated bubble map of any folder or of the whole disk. Hover to read, click to zoom in.

</td>
<td width="33%" valign="top">

### ☁️ Cloud Storage
iCloud Drive, Google Drive, OneDrive, Dropbox: free local copies without deleting anything from the cloud.

</td>
<td width="33%" valign="top">

### ♾️ Menu bar
CPU, GPU, memory, disk, network and battery at a glance, plus one-click Checkup, Security scan and RAM release.

</td>
</tr>
</table>

---

## A quick tour

<table>
<tr>
<td width="50%" align="center">
<img src="docs/screenshots/cleanup.png" alt="Cleanup results"><br>
<b>Cleanup</b>: what was found, by category. Review any item before it goes.
</td>
<td width="50%" align="center">
<img src="docs/screenshots/security.png" alt="Security overview"><br>
<b>Security</b>: Apple's malware signatures, startup items, privacy traces and permissions.
</td>
</tr>
<tr>
<td width="50%" align="center">
<img src="docs/screenshots/storage-map.png" alt="Storage Map"><br>
<b>Storage Map</b>: bubbles grow when you hover them and zoom in when you click.
</td>
<td width="50%" align="center">
<img src="docs/screenshots/declutter.png" alt="Similar photos"><br>
<b>Declutter</b>: look-alike shots grouped by Apple Vision, the best one kept.
</td>
</tr>
<tr>
<td width="50%" align="center">
<img src="docs/screenshots/optimization.png" alt="Maintenance tasks"><br>
<b>Optimization</b>: proven maintenance scripts, one password prompt at most.
</td>
<td width="50%" align="center">
<img src="docs/screenshots/cloud.png" alt="Cloud Storage"><br>
<b>Cloud Storage</b>: see what your cloud folders keep on disk and free it.
</td>
</tr>
</table>

<table>
<tr>
<td width="40%" align="center">
<img src="docs/screenshots/menubar.png" width="300" alt="Menu bar monitor">
</td>
<td width="60%" valign="middle">

### ♾️ Always one click away

Click the infinity icon in the menu bar to see your Mac's vitals live:

- **CPU and GPU load**, sampled from the kernel and the graphics driver
- **Memory used**, with the same definition as Activity Monitor
- **Disk space, network speed and battery**
- **Quick actions**: start a Checkup, run a Security scan or free up RAM without opening the main window

</td>
</tr>
</table>

---

## Safe by design

A cleaner touches your files, so Revive is careful at every step.

| Guard | What it means for you |
|---|---|
| **Review before removal** | Every scan ends on a summary you can inspect item by item. Nothing is removed silently. |
| **Trash first** | Items go to the Trash and can be restored. Only items already in a Trash are deleted for good, when you empty it. |
| **Safety guard** | Each item is re-checked right before it is touched. System locations, keychains, iCloud and cloud folders, Mail and Messages databases, Apple's own apps and data, and caches macOS cannot rebuild are always refused. Symbolic links are resolved first. |
| **Running apps respected** | Caches of open apps start unchecked; apps are quit before being uninstalled. |
| **Strict uninstaller** | Only files named exactly after an app's bundle identifier or name are proposed. |
| **Simulation mode** | Run every flow without changing anything (Settings). |
| **Exclusions** | Folders you list are never scanned or touched. |
| **Closed admin helper** | Administrator tasks run from a fixed list of commands, only for a Revive app signed by the same team. |

---

## How Revive compares

|  | **Revive** | CleanMyMac | Mac Sai | PureMac | Pearcleaner |
|---|:---:|:---:|:---:|:---:|:---:|
| **Price** | Free | Subscription | Free | Free | Free |
| **License** | ✅ GPL-3.0 | ❌ Closed | ✅ BSD-3 | ✅ MIT | ➖ Source-available |
| **One-click checkup** | ✅ | ✅ | ✅ | ➖ | ❌ |
| **System junk cleanup** | ✅ | ✅ | ✅ | ✅ | ➖ |
| **AI caches and models** | ✅ | ✅ | ✅ | – | – |
| **Malware scan with Apple's XProtect YARA rules** | ✅ Full rules | ➖ Own engine | ➖ Hash matching | ❌ | ❌ |
| **Browser privacy and extensions** | ✅ | ✅ | ✅ | ❌ | ❌ |
| **Uninstaller with leftovers** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **App updates** (Sparkle, App Store, Homebrew) | ✅ | ✅ | ➖ Sparkle | ➖ Homebrew | ✅ |
| **Duplicates and similar photos** | ✅ | ✅ | ➖ Duplicates | ✅ | ❌ |
| **Visual disk map** | ✅ Bubbles | ✅ Bubbles | ✅ Treemap | ✅ | ❌ |
| **Cloud storage local copies** | ✅ | ✅ | – | – | – |
| **Menu bar monitor** | ✅ | ✅ | ✅ | – | ❌ |
| **Maintenance scripts** | ✅ | ✅ | ✅ | – | ❌ |
| **Signed and notarized by Apple** | ⏳ Planned | ✅ | ✅ | ✅ | ✅ |
| **Languages** | EN, FR | Many | 7 | 11 | – |

<sub>✅ yes · ➖ partial · ❌ no · – not documented. Based on each project's public documentation in October 2026. Something out of date? Open an issue.</sub>

> CleanMyMac is a polished product and a great choice if you want a supported, paid app. Revive is for people who prefer readable source code and no subscription. Revive is an independent project, not affiliated with MacPaw.

---

## Install

1. Download **[the latest DMG](https://github.com/mbielle/revive/releases/latest)**, open it and drag **Revive** to **Applications**.
2. **First launch:** Revive is not signed with an Apple Developer ID yet, so macOS blocks it the first time. Open it once, then go to **System Settings › Privacy & Security** and click **Open Anyway**. You only do this once.
3. Give Revive **Full Disk Access** when it asks: without it, macOS hides Mail, Safari, the Trash and app data from every app.

Until releases are signed, tasks marked with a lock ask for your administrator password instead of using the helper.

**Requirements:** macOS 14 Sonoma or later, Apple silicon or Intel.

---

## Under the hood

| Need | How Revive does it |
|---|---|
| **Malware signatures** | Apple ships its XProtect YARA rules on every Mac. Revive compiles them with a vendored [YARA](https://github.com/VirusTotal/yara) 4.5.4 (CommonCrypto hashing, no OpenSSL) and scans startup programs, apps, Downloads and Desktop; the deep scan covers more folders. |
| **Persistence check** | Launch agents and daemons are inspected the way Objective-See's KnockKnock does: unsigned programs or ones hiding in temporary folders are flagged. |
| **Junk rules** | Plain JSON files. Adding a rule needs no Swift code, and the test suite checks every rule against the safety guard. |
| **Similar photos** | Apple Vision feature prints, compared between neighboring shots, on device. |
| **Administrator tasks** | A privileged helper (SMAppService launch daemon, XPC) that runs a closed list of commands. Without it, macOS's own password prompt is used. |
| **Metrics** | `host_processor_info`, `vm_statistics64`, IOKit accelerator statistics and power sources. |

---

## Build from source

```bash
brew install xcodegen
git clone https://github.com/mbielle/revive.git
cd revive
xcodegen generate
open Revive.xcodeproj
```

Press ⌘R. Run the engine tests with `cd Packages/ReviveKit && swift test`, and package a DMG with `scripts/make-dmg.sh`.

<details>
<summary><b>Try it on fake data</b></summary>
<br>

```bash
swift scripts/make-demo-home.swift /tmp/ReviveDemo
open build/DerivedData/Build/Products/Debug/Revive.app --args -home /tmp/ReviveDemo -dryRun YES
```

Debug builds then scan a generated folder full of junk, duplicates, similar photos, a fake cloud drive and a suspicious startup item, instead of your home folder.

</details>

<details>
<summary><b>Project layout</b></summary>
<br>

```
App/                      SwiftUI app: design system, one folder per module, menu bar, settings
Helper/                   Privileged helper (launch daemon) and its launchd plist
Packages/ReviveKit/       Engine, testable without UI
  Sources/ReviveKit/      SafetyGuard, rules, scanners, removal, helper XPC, metrics
  Sources/CYara/          Vendored libyara (BSD-3-Clause)
  Tests/                  Swift Testing suite on throwaway fake home folders
Config/                   Signing settings (ad-hoc by default)
scripts/                  Demo home generator, DMG packaging
project.yml               XcodeGen spec (the .xcodeproj is generated)
```

</details>

<details>
<summary><b>Adding a cleanup rule</b></summary>
<br>

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

Then run `swift test` in `Packages/ReviveKit`.

</details>

---

## Contributing

Contributions are welcome, especially cleanup rules and translations. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Revive is free software under the [GNU General Public License v3.0](LICENSE). Credits for the open source projects it builds on are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

<p align="center">
  <sub>Made in France by <a href="https://github.com/mbielle">Mathieu Bielle</a>.</sub>
</p>
