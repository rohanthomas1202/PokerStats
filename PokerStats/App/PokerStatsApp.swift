import SwiftUI
import SwiftData

@main
struct PokerStatsApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try AppGroupContainer.createSharedModelContainer()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}
