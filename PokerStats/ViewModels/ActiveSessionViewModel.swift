import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class ActiveSessionViewModel {
    let session: Session
    private let modelContext: ModelContext

    var isShowingHandLogger = false
    var isShowingRebuy = false
    var isShowingEndSession = false
    var isShowingNoteEditor = false
    var isShowingStaleAlert = false
    var isShowingMentalCheck = false

    var rebuyAmountText: String = ""
    var sessionNotes: String = ""
    var tiltLevel: Int = 3
    var energyLevel: Int = 3
    var focusLevel: Int = 3

    init(session: Session, modelContext: ModelContext) {
        self.session = session
        self.modelContext = modelContext
        self.sessionNotes = session.notes
        self.tiltLevel = session.tiltLevel ?? 3
        self.energyLevel = session.energyLevel ?? 3
        self.focusLevel = session.focusLevel ?? 3

        // Check if session is stale on init
        if SessionRecoveryService.isSessionStale(session) {
            isShowingStaleAlert = true
        }
    }

    // MARK: - Computed Properties

    var elapsed: TimeInterval {
        session.duration
    }

    var handCount: Int {
        session.handCount
    }

    var runningProfitLoss: Double {
        -session.totalInvested // During session, P/L is negative (all money invested, no cash-out yet)
    }

    var sessionStats: ComputedStats {
        StatCalculator.computeSessionStats(session: session)
    }

    var recentHands: [Hand] {
        session.hands
            .sorted { $0.handNumber > $1.handNumber }
            .prefix(5)
            .map { $0 }
    }

    // MARK: - Actions

    func addHand(_ hand: Hand) {
        hand.session = session
        hand.handNumber = session.nextHandNumber
        session.hands.append(hand)
        try? modelContext.save()
    }

    func deleteHand(_ hand: Hand) {
        session.hands.removeAll { $0.id == hand.id }
        modelContext.delete(hand)
        try? modelContext.save()
    }

    func addRebuy() {
        guard let amount = Double(rebuyAmountText), amount > 0 else { return }
        session.rebuys += amount
        rebuyAmountText = ""
        try? modelContext.save()
    }

    func endSession(cashOut: Double, tipRake: Double = 0) {
        session.cashOut = cashOut
        session.tipRake = tipRake
        session.endTime = .now
        session.status = .completed
        session.notes = sessionNotes
        try? modelContext.save()
    }

    func abandonSession() {
        session.endTime = .now
        session.status = .completed
        session.cashOut = 0
        session.notes = sessionNotes
        try? modelContext.save()
    }

    func saveNotes() {
        session.notes = sessionNotes
        try? modelContext.save()
    }

    func saveMentalLevels() {
        session.tiltLevel = tiltLevel
        session.energyLevel = energyLevel
        session.focusLevel = focusLevel
        try? modelContext.save()
    }
}
