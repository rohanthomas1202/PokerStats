import ActivityKit
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

    private var liveActivity: Activity<SessionActivityAttributes>?

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

        // Resume or start Live Activity
        resumeOrStartLiveActivity()
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
        updateLiveActivity()
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
        updateLiveActivity()
    }

    func endSession(cashOut: Double, tipRake: Double = 0) {
        session.cashOut = cashOut
        session.tipRake = tipRake
        session.endTime = .now
        session.status = .completed
        session.notes = sessionNotes
        try? modelContext.save()
        endLiveActivity()
    }

    func abandonSession() {
        session.endTime = .now
        session.status = .completed
        session.cashOut = 0
        session.notes = sessionNotes
        try? modelContext.save()
        endLiveActivity()
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

    // MARK: - Live Activity

    private func resumeOrStartLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Check if there's an existing activity for this session
        let existing = Activity<SessionActivityAttributes>.activities.first { activity in
            activity.attributes.startTime == session.startTime
        }

        if let existing {
            liveActivity = existing
            updateLiveActivity()
        } else {
            startLiveActivity()
        }
    }

    func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = SessionActivityAttributes(
            stakes: session.stakes,
            location: session.location,
            startTime: session.startTime
        )
        let state = SessionActivityAttributes.ContentState(
            handCount: session.handCount,
            totalInvested: session.totalInvested
        )

        do {
            let content = ActivityContent(state: state, staleDate: nil)
            liveActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            // Live Activity not available — silently ignore
        }
    }

    func updateLiveActivity() {
        guard let liveActivity else { return }

        let state = SessionActivityAttributes.ContentState(
            handCount: session.handCount,
            totalInvested: session.totalInvested
        )
        let content = ActivityContent(state: state, staleDate: nil)

        Task {
            await liveActivity.update(content)
        }
    }

    func endLiveActivity() {
        guard let liveActivity else { return }

        let finalState = SessionActivityAttributes.ContentState(
            handCount: session.handCount,
            totalInvested: session.totalInvested
        )
        let content = ActivityContent(state: finalState, staleDate: nil)

        Task {
            await liveActivity.end(content, dismissalPolicy: .default)
        }
        self.liveActivity = nil
    }
}
