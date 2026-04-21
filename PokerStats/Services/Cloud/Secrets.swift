import Foundation

enum Secrets {
    private static let values: [String: String] = {
        // Load from Secrets.plist (generated at build time from .env)
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] else {
            // Fallback: try loading .env directly (for development)
            return loadDotEnv()
        }
        return dict
    }()

    static var supabaseURL: String {
        values["SUPABASE_URL"] ?? "https://YOUR_PROJECT_REF.supabase.co"
    }

    static var supabaseAnonKey: String {
        values["SUPABASE_ANON_KEY"] ?? "YOUR_ANON_KEY"
    }

    // MARK: - .env fallback (development only)

    private static func loadDotEnv() -> [String: String] {
        // Walk up from the bundle to find .env in the project root
        // This only works in debug/simulator builds
        #if DEBUG
        let candidates = [
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // Cloud/
                .deletingLastPathComponent() // Services/
                .deletingLastPathComponent() // PokerStats/
                .deletingLastPathComponent() // project root
                .appendingPathComponent(".env")
        ]

        for url in candidates {
            if let contents = try? String(contentsOf: url, encoding: .utf8) {
                return parseEnv(contents)
            }
        }
        #endif
        return [:]
    }

    private static func parseEnv(_ contents: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            result[key] = value
        }
        return result
    }
}
