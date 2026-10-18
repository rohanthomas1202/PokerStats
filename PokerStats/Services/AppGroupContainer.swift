import Foundation
import SwiftData
import os

enum AppGroupContainer {
    static let appGroupIdentifier = "group.com.rohanthomas.PokerStats"

    enum ContainerError: LocalizedError, Equatable {
        case appGroupUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .appGroupUnavailable(let identifier):
                return "App Group container '\(identifier)' is unavailable. "
                    + "Check that the app is signed with the App Group entitlement."
            }
        }
    }

    private static let logger = Logger(subsystem: "com.rohanthomas.PokerStats", category: "AppGroupContainer")

    /// The shared App Group directory, or nil when the process isn't entitled to it
    /// (for example an unsigned simulator build in CI).
    static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    /// True when this process is the host app for an XCTest / Swift Testing run.
    static var isRunningAsTestHost: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil
            || env["XCTestBundlePath"] != nil
            || env["XCTestSessionIdentifier"] != nil
    }

    @MainActor
    static func createSharedModelContainer() throws -> ModelContainer {
        try makeModelContainer(groupURL: sharedContainerURL, isTestHost: isRunningAsTestHost)
    }

    /// Builds the SwiftData container in the App Group directory.
    ///
    /// If the App Group is unavailable, only a unit-test host falls back, and only to a
    /// throwaway in-memory store. A normal launch throws `ContainerError` so a signing or
    /// entitlement problem fails loudly instead of silently splitting data from the widget.
    @MainActor
    static func makeModelContainer(groupURL: URL?, isTestHost: Bool) throws -> ModelContainer {
        let schema = Schema([Session.self, Hand.self, Settings.self])

        guard let groupURL else {
            if isTestHost {
                logger.warning("App Group unavailable in test host; using in-memory store")
                let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                return try ModelContainer(for: schema, configurations: [config])
            }
            logger.fault("App Group container \(appGroupIdentifier, privacy: .public) is unavailable")
            throw ContainerError.appGroupUnavailable(appGroupIdentifier)
        }

        let config = ModelConfiguration(
            "PokerStats",
            schema: schema,
            url: groupURL.appendingPathComponent("PokerStats.store")
        )
        return try ModelContainer(for: schema, configurations: [config])
    }
}
