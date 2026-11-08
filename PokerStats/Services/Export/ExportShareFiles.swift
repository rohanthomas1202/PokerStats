import Foundation

/// Owns only this export's scratch directory, never the account's model files.
struct ExportShareFiles: Equatable, Sendable {
    let directory: URL
    var urls: [URL] {
        ["sessions.csv", "hands.csv", "pokerstats-export.json"].map {
            directory.appendingPathComponent($0)
        }
    }

    static func write(_ files: ExportFiles, under root: URL = FileManager.default.temporaryDirectory,
                      fileManager: FileManager = .default) throws -> Self {
        let result = Self(directory: root.appendingPathComponent(UUID().uuidString, isDirectory: true))
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

    func remove(fileManager: FileManager = .default) throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }
}
