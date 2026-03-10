import Foundation
import SwiftData

@Model
final class Settings {
    var id: UUID
    var defaultGameType: GameType
    var defaultStakes: String
    var defaultBuyIn: Double
    var currency: String

    init(
        id: UUID = UUID(),
        defaultGameType: GameType = .cash,
        defaultStakes: String = "1/2",
        defaultBuyIn: Double = 200,
        currency: String = "USD"
    ) {
        self.id = id
        self.defaultGameType = defaultGameType
        self.defaultStakes = defaultStakes
        self.defaultBuyIn = defaultBuyIn
        self.currency = currency
    }
}
