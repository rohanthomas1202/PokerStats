import Foundation
import SwiftData
import Testing
@testable import PokerStats

@Suite("Settings export")
@MainActor
struct ExportShareTests {
    @Test func feature_isOffInOnePointZero() {
        #expect(!ExportFeature.isEnabled)
    }

    @Test func footer_explainsSharingAndFileFormats() {
        #expect(ExportShareRow.footer == "Creates three files with all your sessions and hands. Anyone you share them with can see your results. The JSON file keeps every detail. The CSV files open in spreadsheet apps.")
    }

    @Test func writer_sweepsOnlyExportDirectoriesBeforeWriting() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? manager.removeItem(at: root) }
        let input = ExportFiles(sessionsCSV: Data(), handsCSV: Data(), json: Data())
        let previous = try ExportShareFiles.write(input, under: root)
        let unrelated = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let similarName = root.appendingPathComponent("pokerstats-export-unrelated", isDirectory: true)
        for directory in [unrelated, similarName] {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("keep".utf8).write(to: directory.appendingPathComponent("keep.txt"))
        }
        let next = try ExportShareFiles.write(input, under: root)
        #expect(!manager.fileExists(atPath: previous.directory.path))
        for directory in [unrelated, similarName] {
            #expect(try Data(contentsOf: directory.appendingPathComponent("keep.txt")) == Data("keep".utf8))
        }
        #expect(next.urls.map(\.lastPathComponent) == ["sessions.csv", "hands.csv", "pokerstats-export.json"])
        #expect(next.urls.allSatisfy { manager.fileExists(atPath: $0.path) })
    }

    @Test func writer_usesOnlyNeutralNamesAndDefaultProtection_thenRemovesFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = ExportFiles(sessionsCSV: Data("sessions".utf8), handsCSV: Data("hands".utf8), json: Data("json".utf8))
        let files = try ExportShareFiles.write(input, under: root)
        #expect(files.urls.map(\.lastPathComponent) == ["sessions.csv", "hands.csv", "pokerstats-export.json"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: files.directory.path).sorted() == files.urls.map(\.lastPathComponent).sorted())
        #expect(try files.urls.map { try Data(contentsOf: $0) } == [input.sessionsCSV, input.handsCSV, input.json])

        // Compare to an ordinary default-protected write on the same filesystem.
        let control = root.appendingPathComponent("control")
        try Data().write(to: control)
        let expected = try FileManager.default.attributesOfItem(atPath: control.path)[.protectionKey] as? String
        for url in files.urls {
            #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.protectionKey] as? String == expected)
        }
        try files.remove()
        #expect(!FileManager.default.fileExists(atPath: files.directory.path))
        try files.remove() // Dismissing an already-cleaned flow is harmless.
    }

    @Test func progress_yieldsMainActorWhileGenerating_thenPublishesThreeURLs() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = ExportShareViewModel()
        var announcements: [String] = []
        model.announce = { announcements.append($0) }
        let gate = DispatchSemaphore(value: 0)
        let (events, started) = AsyncStream<Void>.makeStream()
        let task = Task {
            await model.prepare {
                #expect(!Thread.isMainThread)
                started.yield(())
                #expect(gate.wait(timeout: .now() + 10) == .success)
                return try ExportShareFiles.write(ExportEngine.makeFiles(sessions: [], hands: [], settings: Settings()), under: root)
            }
        }
        var iterator = events.makeAsyncIterator()
        _ = await iterator.next()
        #expect(model.state == .generating)
        #expect(announcements.isEmpty)
        // Executing here while the worker is blocked proves the UI actor is free.
        gate.signal()
        await task.value
        guard case .ready(let files) = model.state else {
            Issue.record("Expected ready export")
            return
        }
        #expect(files.urls.count == 3)
        #expect(files.urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        #expect(announcements == ["Export ready"])
        let (removingEvents, removing) = AsyncStream<Void>.makeStream()
        let cleanup = Task {
            await model.cleanup { files in
                removing.yield(())
                #expect(gate.wait(timeout: .now() + 10) == .success)
                try files.remove()
            }
        }
        var removingIterator = removingEvents.makeAsyncIterator()
        _ = await removingIterator.next()
        #expect(model.state == .removing)
        #expect(announcements == ["Export ready"])
        gate.signal()
        await cleanup.value
        #expect(model.state == .idle)
        #expect(announcements == ["Export ready"])
        #expect(!FileManager.default.fileExists(atPath: files.directory.path))
    }

    @Test func savedAccount_exportsEverySessionAndHandAndMoneyTotals() async throws {
        let container = try TestHelpers.createContainer()
        let context = container.mainContext
        let sessions = [Session(buyIn: 100, cashOut: 150), Session(buyIn: 200, cashOut: 175)]
        for session in sessions { context.insert(session) }
        for index in 0..<3 {
            let hand = Hand(handNumber: index + 1)
            context.insert(hand)
            hand.session = sessions[index % sessions.count]
        }
        context.insert(Settings(currency: "CAD"))
        try context.save()
        let model = ExportShareViewModel()
        await model.prepare(container: container)
        guard case .ready(let files) = model.state else {
            Issue.record("Expected saved account export")
            return
        }
        let document = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: files.urls[2])) as? [String: Any])
        let sessionRows = try #require(document["sessions"] as? [[String: Any]])
        let handRows = try #require(document["hands"] as? [[String: Any]])
        #expect(sessionRows.count == sessions.count)
        #expect(handRows.count == 3)
        #expect(sessionRows.allSatisfy { $0["currency"] as? String == "CAD" })
        let invested = try sessionRows.map { try #require($0["buy_in"] as? Double) }.reduce(0, +)
        let returned = try sessionRows.map { try #require($0["cash_out"] as? Double) }.reduce(0, +)
        #expect(invested == 300)
        #expect(returned - invested == 25)
        // These test rows have no embedded newlines; the engine suite also tests multiline CSV.
        #expect(try String(contentsOf: files.urls[0], encoding: .utf8).split(separator: "\n").count - 1 == sessions.count)
        #expect(try String(contentsOf: files.urls[1], encoding: .utf8).split(separator: "\n").count - 1 == 3)
        await model.cleanup()
    }

    @Test func engineFailures_showErrorAndAllowRetry() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = ExportShareViewModel()
        var announcements: [String] = []
        model.announce = { announcements.append($0) }
        await model.prepare {
            try ExportShareFiles.write(ExportEngine.makeFiles(sessions: [], hands: [Hand()], settings: Settings()), under: root)
        }
        #expect(model.state == .failed)
        #expect(announcements == ["Couldn't export your data. Please try again."])
        await model.prepare {
            let session = Session()
            session.tableConfigData = Data("invalid JSON".utf8)
            return try ExportShareFiles.write(ExportEngine.makeFiles(sessions: [session], hands: [], settings: Settings()), under: root)
        }
        #expect(model.state == .failed)
        #expect(announcements == Array(repeating: "Couldn't export your data. Please try again.", count: 2))
        await model.prepare {
            try ExportShareFiles.write(ExportEngine.makeFiles(sessions: [], hands: [], settings: Settings()), under: root)
        }
        guard case .ready = model.state else {
            Issue.record("Expected retry to succeed")
            return
        }
        #expect(announcements == ["Couldn't export your data. Please try again.", "Couldn't export your data. Please try again.", "Export ready"])
        await model.cleanup()
    }

    @Test func cleanupFailure_keepsOwnershipAndAllowsRetry() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        enum Failure: Error { case denied }
        let model = ExportShareViewModel()
        var announcements: [String] = []
        model.announce = { announcements.append($0) }
        await model.prepare {
            try ExportShareFiles.write(ExportEngine.makeFiles(sessions: [], hands: [], settings: Settings()), under: root)
        }
        guard case .ready(let files) = model.state else {
            Issue.record("Expected files to clean up")
            return
        }
        await model.cleanup { _ in throw Failure.denied }
        #expect(model.state == .cleanupFailed(files))
        #expect(announcements == ["Export ready", "Couldn't remove the temporary files. Please try again."])
        #expect(FileManager.default.fileExists(atPath: files.directory.path))
        await model.cleanup()
        #expect(model.state == .idle)
        #expect(announcements == ["Export ready", "Couldn't remove the temporary files. Please try again."])
        #expect(!FileManager.default.fileExists(atPath: files.directory.path))
    }

    @Test(arguments: [false, true])
    func dismissalDuringGeneration_removesLateFilesWithoutPresentingThem(removeFails: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        enum Failure: Error { case denied }
        let model = ExportShareViewModel()
        var announcements: [String] = []
        model.announce = { announcements.append($0) }
        let (removalEvents, removed) = AsyncStream<ExportShareFiles>.makeStream()
        let gate = DispatchSemaphore(value: 0)
        let (events, started) = AsyncStream<ExportShareFiles>.makeStream()
        let task = Task {
            await model.prepare(remove: { files in
                removed.yield(files)
                if removeFails { throw Failure.denied }
                try files.remove()
            }) {
                defer { started.finish() }
                let files = try ExportShareFiles.write(ExportEngine.makeFiles(sessions: [], hands: [], settings: Settings()), under: root)
                started.yield(files)
                #expect(gate.wait(timeout: .now() + 10) == .success)
                return files
            }
        }
        var iterator = events.makeAsyncIterator()
        let files = await iterator.next()
        await model.cleanup()
        gate.signal()
        await task.value
        #expect(model.state == .idle)
        #expect(announcements.isEmpty)
        let yieldedFiles = try #require(files)
        removed.finish()
        var removalIterator = removalEvents.makeAsyncIterator()
        let removedFiles = try #require(await removalIterator.next())
        #expect(removedFiles == yieldedFiles)
        #expect(FileManager.default.fileExists(atPath: yieldedFiles.directory.path) == removeFails)
    }
}
