// Builds a fake home folder full of realistic clutter, to try Lucent without touching your files.
//
//   swift scripts/make-demo-home.swift /tmp/LucentDemo
//   open build/.../Lucent.app --args -home /tmp/LucentDemo -dryRun YES
//
// Debug builds read `-home` and scan that folder instead of yours.

import AppKit
import Foundation

let root = URL(filePath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/LucentDemo")
let fm = FileManager.default
try? fm.removeItem(at: root)

@discardableResult
func file(_ path: String, megabytes: Double = 0.05, byte: UInt8 = 0x2A, daysOld: Double = 0) -> URL {
    let url = root.appending(path: path)
    try! fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    // Random-ish content so files are really allocated and not deduplicated.
    var data = Data(count: Int(megabytes * 1_000_000))
    data.withUnsafeMutableBytes { buffer in
        for i in stride(from: 0, to: buffer.count, by: 4096) { buffer[i] = byte &+ UInt8(truncatingIfNeeded: i / 4096) }
    }
    try! data.write(to: url)
    if daysOld > 0 {
        let date = Date.now.addingTimeInterval(-daysOld * 86_400)
        try! fm.setAttributes([.modificationDate: date], ofItemAtPath: url.path(percentEncoded: false))
    }
    return url
}

func copy(_ source: URL, to path: String) {
    let url = root.appending(path: path)
    try! fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! fm.copyItem(at: source, to: url)
}

func text(_ path: String, _ content: String) {
    let url = root.appending(path: path)
    try! fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! content.write(to: url, atomically: true, encoding: .utf8)
}

/// A photo-like picture: sky gradient, sun and hills. `variant` shifts it slightly like a retake.
func photo(_ path: String, variant: Int, seed: Int) {
    let size = NSSize(width: 1200, height: 800)
    let image = NSImage(size: size)
    image.lockFocus()
    let hue = CGFloat(seed % 7) / 7
    NSGradient(colors: [NSColor(hue: hue, saturation: 0.5, brightness: 0.95, alpha: 1),
                        NSColor(hue: hue, saturation: 0.7, brightness: 0.55, alpha: 1)])!
        .draw(in: NSRect(origin: .zero, size: size), angle: -90)
    let dx = CGFloat(variant) * 14
    NSColor(hue: 0.12, saturation: 0.8, brightness: 1, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 780 + dx, y: 520, width: 160, height: 160)).fill()
    NSColor(hue: 0.3 + CGFloat(seed % 3) / 10, saturation: 0.6, brightness: 0.45, alpha: 1).setFill()
    let hills = NSBezierPath()
    hills.move(to: .zero)
    hills.curve(to: NSPoint(x: 1200, y: 0), controlPoint1: NSPoint(x: 300 + dx, y: 520), controlPoint2: NSPoint(x: 800, y: 120))
    hills.fill()
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let url = root.appending(path: path)
    try! fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9 - Double(variant) * 0.05])!.write(to: url)
}

// System junk
file("Library/Caches/com.spotify.client/Data/cache.bin", megabytes: 60)
file("Library/Caches/com.tinyspeck.slackmacgap/Cache.db", megabytes: 25)
file("Library/Caches/Homebrew/downloads/node.tar.gz", megabytes: 40)
file("Library/Caches/CloudKit/db", megabytes: 5) // protected: never proposed
file("Library/Logs/DiagnosticReports/App_2025.ips", megabytes: 2)
file("Library/Logs/com.example.app/app.log", megabytes: 8)
file("Library/Saved Application State/com.example.app.savedState/data.data", megabytes: 1, daysOld: 30)
file("Library/Developer/Xcode/DerivedData/MyApp-abcdef/Build/app.o", megabytes: 120)
file("Library/Developer/Xcode/iOS DeviceSupport/iPhone 17 (26.0)/Symbols/dyld", megabytes: 90)
file(".npm/_cacache/content-v2/sha512/aa/bb", megabytes: 30)

// AI clutter
file("Library/Caches/com.openai.chat/Cache.db", megabytes: 35)
file("Library/Application Support/Claude/Cache/data_1", megabytes: 20)
file("Library/Caches/pip/http/wheels.bin", megabytes: 45)
file(".cache/huggingface/hub/models--tiny-llama/blobs/model.safetensors", megabytes: 150)

// Mail and Trash
file("Library/Containers/com.apple.mail/Data/Library/Mail Downloads/4F2A/Invoice.pdf", megabytes: 3)
file("Library/Containers/com.apple.mail/Data/Library/Mail Downloads/91BC/Photos.zip", megabytes: 18)
file(".Trash/Old Presentation.key", megabytes: 22)
file(".Trash/installer.dmg", megabytes: 30)

// Leftovers of an uninstalled app
file("Library/Preferences/com.gone.OldEditor.plist", megabytes: 0.01)
file("Library/Containers/com.gone.OldEditor/Data/Library/data.db", megabytes: 12)
file("Library/Application Support/com.gone.OldEditor/templates.bin", megabytes: 6)

// Installers
file("Downloads/Figma-Setup.dmg", megabytes: 48)
file("Downloads/Tool-Installer.pkg", megabytes: 15)

// Duplicates
let report = file("Documents/Reports/Annual Report.pdf", megabytes: 4, byte: 7, daysOld: 400)
copy(report, to: "Downloads/Annual Report.pdf")
copy(report, to: "Desktop/Annual Report copy.pdf")
let video = file("Movies/Holiday.mov", megabytes: 70, byte: 9, daysOld: 500)
copy(video, to: "Downloads/Holiday (1).mov")

// Large and old
file("Movies/Screen Recording 2024.mov", megabytes: 85, byte: 3, daysOld: 600)
file("Documents/Archive/Backup-2023.zip", megabytes: 55, byte: 4, daysOld: 700)
file("Documents/Old Project/render.psd", megabytes: 14, byte: 5, daysOld: 420)

// Similar photos and screenshots
for seed in 0..<3 {
    for variant in 0..<3 {
        photo("Pictures/Trip/IMG_\(1000 + seed * 10 + variant).jpg", variant: variant, seed: seed)
    }
}
for index in 0..<6 {
    photo("Desktop/Screenshot 2026-0\(index + 1)-12 at 10.0\(index).00.png", variant: index % 2, seed: 10 + index)
}

// Cloud storage and a local copy of a cloud file
let cloudFile = file("Library/CloudStorage/GoogleDrive-demo@gmail.com/My Drive/Videos/Wedding.mp4", megabytes: 40, byte: 11)
copy(cloudFile, to: "Downloads/Wedding.mp4")
file("Library/CloudStorage/GoogleDrive-demo@gmail.com/My Drive/Docs/Budget.xlsx", megabytes: 2, byte: 12)
file("Library/CloudStorage/OneDrive-Personal/Photos/Album.zip", megabytes: 25, byte: 13)

// Browser traces and an extension
let chrome = "Library/Application Support/Google/Chrome/Default"
file("\(chrome)/History", megabytes: 6)
file("\(chrome)/Cookies", megabytes: 1)
file("\(chrome)/Web Data", megabytes: 2)
file("\(chrome)/Login Data", megabytes: 1) // passwords: never proposed
file("\(chrome)/Cache/Cache_Data/data_0", megabytes: 30)
text("\(chrome)/Extensions/cjpalhdlnbpafiamejdnhcphjbkeiagm/1.62.0/manifest.json",
     #"{"name": "uBlock Origin", "version": "1.62.0"}"#)
text("\(chrome)/Extensions/aapbdbdomjkkjkaonfhkkikfgjllcleb/2.0.16/manifest.json",
     #"{"name": "__MSG_appName__", "version": "2.0.16", "default_locale": "en"}"#)
text("\(chrome)/Extensions/aapbdbdomjkkjkaonfhkkikfgjllcleb/2.0.16/_locales/en/messages.json",
     #"{"appName": {"message": "Google Translate"}}"#)
file("Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.RecentDocuments.sfl3", megabytes: 0.02)

// A suspicious startup item: unsigned program hidden in a dot-folder.
let agentFolder = root.appending(path: ".hidden-updater")
try! fm.createDirectory(at: agentFolder, withIntermediateDirectories: true)
let source = agentFolder.appending(path: "agent.c")
try! "int main(void) { return 0; }\n".write(to: source, atomically: true, encoding: .utf8)
let binary = agentFolder.appending(path: "updater")
for (tool, args) in [("/usr/bin/clang", ["-o", binary.path, source.path]), ("/usr/bin/codesign", ["--remove-signature", binary.path])] {
    let process = Process()
    process.executableURL = URL(filePath: tool)
    process.arguments = args
    try! process.run()
    process.waitUntilExit()
}
try! fm.removeItem(at: source)
text("Library/LaunchAgents/com.totally-legit.updater.plist", """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.totally-legit.updater</string>
<key>ProgramArguments</key><array><string>\(binary.path)</string></array>
<key>RunAtLoad</key><true/>
</dict></plist>
""")

for folder in ["Music", "Applications"] { try! fm.createDirectory(at: root.appending(path: folder), withIntermediateDirectories: true) }
print("Demo home ready at \(root.path)")
