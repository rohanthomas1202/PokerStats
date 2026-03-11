import Foundation
import SwiftData

enum AppGroupContainer {
    static let appGroupIdentifier = "group.com.rohanthomas.PokerStats"

    static var sharedContainerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)!
    }

    @MainActor
    static func createSharedModelContainer() throws -> ModelContainer {
        let schema = Schema([Session.self, Hand.self, Settings.self])
        let config = ModelConfiguration(
            "PokerStats",
            schema: schema,
            url: sharedContainerURL.appendingPathComponent("PokerStats.store")
        )
        return try ModelContainer(for: schema, configurations: [config])
    }
}
