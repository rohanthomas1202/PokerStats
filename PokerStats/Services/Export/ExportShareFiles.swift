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
        let result = Self(directory: root.appendingPathComponent(directoryPrefix + UUID().uuidString, isDirectory: true))
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
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .creationDateKey]
        guard let entries = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: keys) else { return }
        // Only our recognizable scratch directories are eligible, never unrelated temporary content.
        for url in entries {
            let name = url.lastPathComponent
            guard name.hasPrefix(directoryPrefix), UUID(uuidString: String(name.dropFirst(directoryPrefix.count))) != nil,
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isDirectory == true, values.isSymbolicLink != true,
                  let created = values.creationDate, now.timeIntervalSince(created) > staleAge else { continue }
            do {
                try fileManager.removeItem(at: url)
            } catch {
                logger.error("Couldn't remove a stale export directory")
            }
        }
    }

    func remove(fileManager: FileManager = .default) throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }
}
