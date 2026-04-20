@preconcurrency import ActivityKit
import Foundation
import SwiftData
import Observation
import WidgetKit

@Observable
@MainActor
final class ActiveSessionViewModel {
    let session: Session
    private let modelContext: ModelContext
    private var authService: AuthService?

    var isShowingHandLogger = false
    var isShowingRebuy = false
    var isShowingEndSession = false
    var isShowingNoteEditor = false
    var isShowingStaleAlert = false
    var isShowingMentalCheck = false
    var isShowingTableSetup = false

    var rebuyAmountText: String = ""
    var sessionNotes: String = ""
    var tiltLevel: Int = 3
    var energyLevel: Int = 3
    var focusLevel: Int = 3

    private var liveActivity: Activity<SessionActivityAttributes>?

    init(session: Session, modelContext: ModelContext, authService: AuthService? = nil) {
        self.session = session
        self.modelContext = modelContext
        self.authService = authService
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

    /// Hero's current position based on table config, or nil if auto-tracking is disabled.
    var currentHeroPosition: SeatPosition? {
        guard let config = session.tableConfig, config.isCalibrated else { return nil }
        let position = PositionTracker.heroPosition(config: config)
        return position == .unknown ? nil : position
    }

    /// Whether auto position tracking is enabled and calibrated.
    var isPositionTrackingActive: Bool {
        session.tableConfig?.isCalibrated ?? false
    }

    /// Whether this is the first hand (position tracking enabled but not yet calibrated).
    var needsPositionCalibration: Bool {
        guard let config = session.tableConfig else { return false }
        return !config.isCalibrated
    }

    // MARK: - Actions

    func addHand(_ hand: Hand) {
        hand.session = session
        hand.handNumber = session.nextHandNumber
        session.hands.append(hand)

        // Auto position tracking: calibrate on first hand, advance button on subsequent hands
        if var config = session.tableConfig {
            if !config.isCalibrated && hand.position != .unknown {
                // First hand: infer button seat from hero's selected position
                config.buttonSeatIndex = PositionTracker.inferButtonSeat(
                    heroSeat: config.heroSeatIndex,
                    heroPosition: hand.position,
                    config: config
                )
                session.tableConfig = config
            }

            // Advance button for the next hand
            if config.isCalibrated {
                let advanced = PositionTracker.advanceButton(config: config)
                session.tableConfig = advanced
            }
        }

        try? modelContext.save()
        Task { await updateLiveActivity() }
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
        Task { await updateLiveActivity() }
    }

    func endSession(cashOut: Double, tipRake: Double = 0) {
        session.cashOut = cashOut
        session.tipRake = tipRake
        session.endTime = .now
        session.status = .completed
        session.notes = sessionNotes
        try? modelContext.save()
        Task { await endLiveActivity() }
        WidgetCenter.shared.reloadAllTimelines()
        autoBackup()
    }

    func abandonSession() {
        session.endTime = .now
        session.status = .completed
        session.cashOut = 0
        session.notes = sessionNotes
        try? modelContext.save()
        Task { await endLiveActivity() }
        WidgetCenter.shared.reloadAllTimelines()
        autoBackup()
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

    // MARK: - Table Management

    func updateTableConfig(_ config: TableConfig) {
        session.tableConfig = config
        try? modelContext.save()
    }

    func removeTablePlayer(at seatIndex: Int) {
        guard let config = session.tableConfig else { return }
        let updated = PositionTracker.removePlayer(at: seatIndex, config: config)
        session.tableConfig = updated
        try? modelContext.save()
    }

    func addTablePlayer(at seatIndex: Int, name: String = "") {
        guard let config = session.tableConfig else { return }
        let updated = PositionTracker.addPlayer(at: seatIndex, name: name, config: config)
        session.tableConfig = updated
        try? modelContext.save()
    }

    func renameTablePlayer(at seatIndex: Int, name: String) {
        guard var config = session.tableConfig else { return }
        guard seatIndex >= 0, seatIndex < config.seats.count else { return }
        config.seats[seatIndex].playerName = name
        session.tableConfig = config
        try? modelContext.save()
    }

    // MARK: - Auto Backup

    private func autoBackup() {
        guard let authService else {
            print("[AutoBackup] Skipped — no authService")
            return
        }
        authService.scheduleBackup(modelContext: modelContext)
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
            Task { await updateLiveActivity() }
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

    func updateLiveActivity() async {
        guard let liveActivity else { return }

        let state = SessionActivityAttributes.ContentState(
            handCount: session.handCount,
            totalInvested: session.totalInvested
        )
        let content = ActivityContent(state: state, staleDate: nil)

        await liveActivity.update(content)
    }

    func endLiveActivity() async {
        guard let liveActivity else { return }

        let finalState = SessionActivityAttributes.ContentState(
            handCount: session.handCount,
            totalInvested: session.totalInvested
        )
        let content = ActivityContent(state: finalState, staleDate: nil)

        await liveActivity.end(content, dismissalPolicy: .default)
        self.liveActivity = nil
    }
}
