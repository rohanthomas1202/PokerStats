import Foundation

/// Owns only this export's scratch directory, never the account's model files.
struct ExportShareFiles: Equatable, Sendable {
    private static let directoryPrefix = "pokerstats-export-"

    let directory: URL
    var urls: [URL] {
        ["sessions.csv", "hands.csv", "pokerstats-export.json"].map {
            directory.appendingPathComponent($0)
        }
    }

    static func write(_ files: ExportFiles, under root: URL = FileManager.default.temporaryDirectory,
                      fileManager: FileManager = .default) throws -> Self {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true, attributes: nil)
        // Only our recognizable scratch directories are eligible, never unrelated temporary content.
        for url in try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            let name = url.lastPathComponent
            guard name.hasPrefix(directoryPrefix), UUID(uuidString: String(name.dropFirst(directoryPrefix.count))) != nil else { continue }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
            try fileManager.removeItem(at: url)
        }
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

    func remove(fileManager: FileManager = .default) throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }
}
