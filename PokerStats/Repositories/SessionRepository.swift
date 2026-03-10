import Foundation
import SwiftData

/// Protocol for session data access. Enables test mocking.
@MainActor
protocol SessionRepositoryProtocol {
    func fetchAll() throws -> [Session]
    func fetchActive() throws -> Session?
    func fetchCompleted() throws -> [Session]
    func save(_ session: Session) throws
    func delete(_ session: Session) throws
    func fetchAllHands() throws -> [Hand]
}

/// SwiftData implementation of SessionRepository.
@MainActor
final class SessionRepository: SessionRepositoryProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() throws -> [Session] {
        let descriptor = FetchDescriptor<Session>(
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchActive() throws -> Session? {
        let active = SessionStatus.active.rawValue
        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate<Session> { $0.statusRaw == active },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).first
    }

    func fetchCompleted() throws -> [Session] {
        let completed = SessionStatus.completed.rawValue
        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate<Session> { $0.statusRaw == completed },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func save(_ session: Session) throws {
        modelContext.insert(session)
        try modelContext.save()
    }

    func delete(_ session: Session) throws {
        modelContext.delete(session)
        try modelContext.save()
    }

    func fetchAllHands() throws -> [Hand] {
        let descriptor = FetchDescriptor<Hand>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
}
