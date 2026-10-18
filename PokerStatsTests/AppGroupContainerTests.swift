import Foundation
import SwiftData
import Testing
@testable import PokerStats

@Suite("App Group Container Tests")
@MainActor
struct AppGroupContainerTests {

    @Test func missingAppGroup_outsideTests_throwsClearError() {
        #expect(throws: AppGroupContainer.ContainerError.appGroupUnavailable(AppGroupContainer.appGroupIdentifier)) {
            _ = try AppGroupContainer.makeModelContainer(groupURL: nil, isTestHost: false)
        }
    }

    @Test func missingAppGroup_inTestHost_usesInMemoryStore() throws {
        let container = try AppGroupContainer.makeModelContainer(groupURL: nil, isTestHost: true)
        #expect(container.configurations.allSatisfy { $0.isStoredInMemoryOnly })
    }

    @Test func availableAppGroup_storesInGroupDirectory() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppGroupContainerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let container = try AppGroupContainer.makeModelContainer(groupURL: dir, isTestHost: false)
        let urls = container.configurations.map(\.url)
        #expect(urls == [dir.appendingPathComponent("PokerStats.store")])
    }

    @Test func errorMessage_namesTheAppGroup() {
        let error = AppGroupContainer.ContainerError.appGroupUnavailable("group.example")
        #expect(error.errorDescription?.contains("group.example") == true)
    }
}
