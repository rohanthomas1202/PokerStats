import Foundation
import SwiftData
import Observation
import WidgetKit

@Observable
@MainActor
final class SettingsViewModel {
    var defaultBuyIn: String = "200"
    var defaultStakes: String = "1/2"
    var defaultGameType: GameType = .cash
    var showDeleteAllConfirmation = false
    var showDeleteAllSecondConfirmation = false

    func loadSettings(from context: ModelContext) {
        let descriptor = FetchDescriptor<Settings>()
        if let settings = try? context.fetch(descriptor).first {
            defaultBuyIn = String(Int(settings.defaultBuyIn))
            defaultStakes = settings.defaultStakes
            defaultGameType = settings.defaultGameType
        }
    }

    func saveSettings(to context: ModelContext) {
        let descriptor = FetchDescriptor<Settings>()
        let settings: Settings
        if let existing = try? context.fetch(descriptor).first {
            settings = existing
        } else {
            settings = Settings()
            context.insert(settings)
        }

        settings.defaultBuyIn = Double(defaultBuyIn) ?? 200
        settings.defaultStakes = defaultStakes
        settings.defaultGameType = defaultGameType
        try? context.save()
    }

    func deleteAllData(from context: ModelContext) {
        do {
            try context.delete(model: Hand.self)
            try context.delete(model: Session.self)
            try context.save()
        } catch {
            // Silently fail for MVP — could add error reporting later
        }
        showDeleteAllSecondConfirmation = false
        WidgetCenter.shared.reloadAllTimelines()
    }
}
