import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class NewSessionViewModel {
    var buyInText: String = "200"
    var selectedStakes: String = "1/2"
    var customStakes: String = ""
    var location: String = ""
    var gameType: GameType = .cash
    var tiltLevel: Int = 3
    var energyLevel: Int = 3
    var focusLevel: Int = 3
    var tableSize: Int = 6

    var isValid: Bool {
        guard let amount = Double(buyInText), amount > 0 else { return false }
        return true
    }

    var buyInAmount: Double {
        Double(buyInText) ?? 0
    }

    var effectiveStakes: String {
        selectedStakes == "Custom" ? customStakes : selectedStakes
    }

    func loadDefaults(from context: ModelContext) {
        let descriptor = FetchDescriptor<Settings>()
        if let settings = try? context.fetch(descriptor).first {
            buyInText = String(Int(settings.defaultBuyIn))
            selectedStakes = settings.defaultStakes
            gameType = settings.defaultGameType
        }
    }

    func createSession(in context: ModelContext) -> Session {
        let session = Session(
            location: location,
            gameType: gameType,
            stakes: effectiveStakes,
            buyIn: buyInAmount
        )
        session.tiltLevel = tiltLevel
        session.energyLevel = energyLevel
        session.focusLevel = focusLevel

        // Set up table config for auto position tracking
        let config = PositionTracker.createConfig(totalSeats: tableSize)
        session.tableConfig = config

        context.insert(session)
        try? context.save()
        return session
    }
}
