import Foundation
import SQLite3

/// A privacy permission granted (or denied) to an app, from macOS's TCC database.
public struct AppPermission: Identifiable, Hashable, Sendable {
    public var id: String { "\(service)-\(client)" }
    public let service: String
    public let client: String
    public let isAllowed: Bool
    public let lastModified: Date?

    /// Name accepted by `tccutil reset`, e.g. "Camera".
    public var serviceShortName: String {
        service.hasPrefix("kTCCService") ? String(service.dropFirst("kTCCService".count)) : service
    }
}

public enum PermissionsReader {
    public enum Failure: Error { case unreadable }

    /// Permissions of the current user. Requires Full Disk Access.
    public static func read(home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> [AppPermission] {
        let databases = [
            home.appending(path: "Library/Application Support/com.apple.TCC/TCC.db"),
            URL(filePath: "/Library/Application Support/com.apple.TCC/TCC.db"),
        ]
        var permissions: [AppPermission] = []
        var readAny = false
        for url in databases {
            guard let rows = try? rows(in: url) else { continue }
            readAny = true
            permissions += rows
        }
        guard readAny else { throw Failure.unreadable }
        var seen = Set<String>()
        return permissions
            .filter { !$0.client.hasPrefix("com.apple.") && !$0.client.hasPrefix("/System/") && !$0.client.hasPrefix("/usr/") }
            .filter { seen.insert($0.id).inserted }
    }

    static func rows(in url: URL) throws -> [AppPermission] {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(url.path(percentEncoded: false), &db, flags, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            throw Failure.unreadable
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        let sql = "SELECT service, client, auth_value, last_modified FROM access"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw Failure.unreadable }
        defer { sqlite3_finalize(statement) }

        var result: [AppPermission] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let service = sqlite3_column_text(statement, 0), let client = sqlite3_column_text(statement, 1) else { continue }
            let modified = sqlite3_column_int64(statement, 3)
            result.append(AppPermission(
                service: String(cString: service),
                client: String(cString: client),
                isAllowed: sqlite3_column_int(statement, 2) == 2,
                lastModified: modified > 0 ? Date(timeIntervalSince1970: TimeInterval(modified)) : nil
            ))
        }
        return result
    }

    /// Removes the app's answer for the service: macOS asks again next time the app needs it.
    public static func reset(_ permission: AppPermission) -> Bool {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/tccutil")
        process.arguments = ["reset", permission.serviceShortName, permission.client]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
