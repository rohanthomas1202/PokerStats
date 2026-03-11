import Foundation
import SwiftData
import Observation
import WidgetKit

@Observable
@MainActor
final class SessionDetailViewModel {
    let session: Session
    private let modelContext: ModelContext

    var isEditing = false
    var editBuyIn: String = ""
    var editCashOut: String = ""
    var editRebuys: String = ""
    var editLocation: String = ""
    var editStakes: String = ""
    var editNotes: String = ""
    var showDeleteConfirmation = false

    init(session: Session, modelContext: ModelContext) {
        self.session = session
        self.modelContext = modelContext
    }

    var stats: ComputedStats {
        StatCalculator.computeSessionStats(session: session)
    }

    var positionStats: [PositionStats] {
        StatCalculator.statsByPosition(hands: session.hands)
    }

    var sortedHands: [Hand] {
        session.hands.sorted { $0.handNumber < $1.handNumber }
    }

    // MARK: - Edit

    func beginEditing() {
        editBuyIn = String(Int(session.buyIn))
        editCashOut = String(Int(session.cashOut))
        editRebuys = String(Int(session.rebuys))
        editLocation = session.location
        editStakes = session.stakes
        editNotes = session.notes
        isEditing = true
    }

    func saveEdits() {
        if let buyIn = Double(editBuyIn) { session.buyIn = buyIn }
        if let cashOut = Double(editCashOut) { session.cashOut = cashOut }
        if let rebuys = Double(editRebuys) { session.rebuys = rebuys }
        session.location = editLocation
        session.stakes = editStakes
        session.notes = editNotes
        try? modelContext.save()
        isEditing = false
    }

    func cancelEditing() {
        isEditing = false
    }

    func deleteSession() {
        modelContext.delete(session)
        try? modelContext.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
