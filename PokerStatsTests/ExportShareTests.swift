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
        let source = try TestHelpers.repositoryFile("PokerStats/Services/Export/ExportShareFiles.swift")
        #expect(source.contains("attributes: nil"))
        #expect(source.contains("data.write(to: url)"))
        #expect(!source.contains("setAttributes"))
        #expect(!source.contains("NSFileProtectionKey"))
        #expect(!source.contains("fileProtection"))
        try files.remove()
        #expect(!FileManager.default.fileExists(atPath: files.directory.path))
        try files.remove() // Dismissing an already-cleaned flow is harmless.
    }

    @Test func progress_yieldsMainActorWhileGenerating_thenPublishesThreeURLs() async throws {
        let model = ExportShareViewModel()
        let gate = DispatchSemaphore(value: 0)
        let (events, started) = AsyncStream<Void>.makeStream()
        let task = Task {
            await model.prepare {
                #expect(!Thread.isMainThread)
                started.yield(())
                #expect(gate.wait(timeout: .now() + 10) == .success)
                return try ExportShareFiles.write(ExportEngine.makeFiles(sessions: [], hands: [], settings: Settings()))
            }
        }
        var iterator = events.makeAsyncIterator()
        _ = await iterator.next()
        #expect(model.state == .generating)
        // Executing here while the worker is blocked proves the UI actor is free.
        gate.signal()
        await task.value
        guard case .ready(let files) = model.state else {
            Issue.record("Expected ready export")
            return
        }
        #expect(files.urls.count == 3)
        #expect(files.urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        await model.cleanup()
        #expect(model.state == .idle)
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
        let model = ExportShareViewModel()
        await model.prepare {
            try ExportShareFiles.write(ExportEngine.makeFiles(sessions: [], hands: [Hand()], settings: Settings()))
        }
        #expect(model.state == .failed)
        await model.prepare {
            let session = Session()
            session.tableConfigData = Data("invalid JSON".utf8)
            return try ExportShareFiles.write(ExportEngine.makeFiles(sessions: [session], hands: [], settings: Settings()))
        }
        #expect(model.state == .failed)
        await model.prepare {
            try ExportShareFiles.write(ExportEngine.makeFiles(sessions: [], hands: [], settings: Settings()))
        }
        guard case .ready = model.state else {
            Issue.record("Expected retry to succeed")
            return
        }
        await model.cleanup()
    }

    @Test func cleanupFailure_keepsOwnershipAndAllowsRetry() async {
        enum Failure: Error { case denied }
        let model = ExportShareViewModel()
        await model.prepare {
            try ExportShareFiles.write(ExportEngine.makeFiles(sessions: [], hands: [], settings: Settings()))
        }
        guard case .ready(let files) = model.state else {
            Issue.record("Expected files to clean up")
            return
        }
        await model.cleanup { _ in throw Failure.denied }
        #expect(model.state == .cleanupFailed(files))
        #expect(FileManager.default.fileExists(atPath: files.directory.path))
        await model.cleanup()
        #expect(model.state == .idle)
        #expect(!FileManager.default.fileExists(atPath: files.directory.path))
    }

    @Test func dismissalDuringGeneration_removesLateFilesWithoutPresentingThem() async {
        let model = ExportShareViewModel()
        let gate = DispatchSemaphore(value: 0)
        let (events, started) = AsyncStream<ExportShareFiles>.makeStream()
        let task = Task {
            await model.prepare {
                defer { started.finish() }
                let files = try ExportShareFiles.write(ExportEngine.makeFiles(sessions: [], hands: [], settings: Settings()))
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
        if let files { #expect(!FileManager.default.fileExists(atPath: files.directory.path)) }
    }
}
