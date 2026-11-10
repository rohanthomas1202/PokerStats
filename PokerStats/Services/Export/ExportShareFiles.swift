import Foundation
import os

/// Owns only this export's scratch directory, never the account's model files.
struct ExportShareFiles: Equatable, Sendable {
    private static let directoryPrefix = "pokerstats-export-"
    /// Younger directories may belong to a live attempt, such as another iPad scene's share sheet.
    static let staleAge: TimeInterval = 60 * 60
    private static let logger = Logger(subsystem: "com.rohanthomas.PokerStats", category: "ExportShareFiles")

    let directory: URL
    var urls: [URL] {
        ["sessions.csv", "hands.csv", "pokerstats-export.json"].map {
            directory.appendingPathComponent($0)
        }
    }

    static func write(_ files: ExportFiles, under root: URL = FileManager.default.temporaryDirectory,
                      fileManager: FileManager = .default, now: Date = .now) throws -> Self {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true, attributes: nil)
        sweepStaleDirectories(under: root, now: now, fileManager: fileManager)
        // The name carries the creation time, so the sweep needs no file timestamp API.
        let name = directoryPrefix + "\(Int(now.timeIntervalSince1970))-" + UUID().uuidString
        let result = Self(directory: root.appendingPathComponent(name, isDirectory: true))
        // No protection attributes or writing options: inherit iOS's default protection.
        try fileManager.createDirectory(at: result.directory, withIntermediateDirectories: true, attributes: nil)
        do {
            for (data, url) in zip([files.sessionsCSV, files.handsCSV, files.json], result.urls) {
                try data.write(to: url)
            }
            return result
        } catch {
            try? result.remove(fileManager: fileManager)
            throw error
        }
    }

    /// Best effort: a leftover that can't be read or removed never blocks a fresh export.
    private static func sweepStaleDirectories(under root: URL, now: Date, fileManager: FileManager) {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let entries = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: keys) else { return }
        // Only our recognizable scratch directories are eligible, never unrelated temporary content.
        for url in entries {
            guard let created = creationTime(ofDirectoryNamed: url.lastPathComponent),
                  now.timeIntervalSince(created) > staleAge,
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isDirectory == true, values.isSymbolicLink != true else { continue }
            do {
                try fileManager.removeItem(at: url)
            } catch {
                let error = error as NSError
                logger.error("Couldn't remove a stale export directory: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
            }
        }
    }

    /// Parses `pokerstats-export-<seconds since 1970>-<UUID>`; nil for any other name.
    private static func creationTime(ofDirectoryNamed name: String) -> Date? {
        guard name.hasPrefix(directoryPrefix) else { return nil }
        let parts = name.dropFirst(directoryPrefix.count).split(separator: "-", maxSplits: 1)
        guard parts.count == 2, let seconds = Int(parts[0]), UUID(uuidString: String(parts[1])) != nil else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    func remove(fileManager: FileManager = .default) throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }
}
