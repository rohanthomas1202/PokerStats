import SwiftUI
import SwiftData

@main
struct PokerStatsApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema([
            Session.self,
            Hand.self,
            Settings.self
        ])
        let config = ModelConfiguration(
            "PokerStats",
            schema: schema
        )
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
