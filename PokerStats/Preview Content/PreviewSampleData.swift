import Foundation
import SwiftData

/// Sample data factories for SwiftUI previews.
enum PreviewSampleData {

    /// Create a sample completed session with hands.
    static func sampleCompletedSession() -> Session {
        let session = Session(
            startTime: Calendar.current.date(byAdding: .hour, value: -4, to: .now)!,
            endTime: .now,
            location: "Bellagio",
            gameType: .cash,
            stakes: "1/2",
            status: .completed,
            buyIn: 200,
            cashOut: 450
        )

        let hands = sampleHands()
        for hand in hands {
            hand.session = session
            session.hands.append(hand)
        }

        return session
    }

    /// Create a sample active session.
    static func sampleActiveSession() -> Session {
        let session = Session(
            startTime: Calendar.current.date(byAdding: .hour, value: -2, to: .now)!,
            location: "Home Game",
            gameType: .cash,
            stakes: "1/2",
            buyIn: 200
        )
        return session
    }

    /// Create a set of sample hands representing typical play.
    static func sampleHands() -> [Hand] {
        [
            // Hand 1: Fold
            Hand(handNumber: 1, preflopAction: .fold),

            // Hand 2: Call, won before showdown
            Hand(handNumber: 2, preflopAction: .call,
                 postflopResult: .wonBeforeShowdown),

            // Hand 3: Fold
            Hand(handNumber: 3, preflopAction: .fold),

            // Hand 4: Raise, no 3-bet, c-bet, won at showdown
            Hand(handNumber: 4, preflopAction: .raise,
                 postflopResult: .wonAtShowdown, didCBet: true),

            // Hand 5: Fold
            Hand(handNumber: 5, preflopAction: .fold),

            // Hand 6: Call, lost at showdown
            Hand(handNumber: 6, preflopAction: .call,
                 postflopResult: .lostAtShowdown),

            // Hand 7: Raise, faced 3-bet, folded
            Hand(handNumber: 7, preflopAction: .raise,
                 faced3Bet: true, threeBetResponse: .folded),

            // Hand 8: Fold
            Hand(handNumber: 8, preflopAction: .fold),

            // Hand 9: Raise, no 3-bet, won preflop
            Hand(handNumber: 9, preflopAction: .raise,
                 postflopResult: .wonPreflop),

            // Hand 10: Call, lost before showdown
            Hand(handNumber: 10, preflopAction: .call,
                 postflopResult: .lostBeforeShowdown),
        ]
    }

    /// Create a model container with sample data for previews.
    @MainActor
    static func previewContainer() -> ModelContainer {
        let schema = Schema([Session.self, Hand.self, Settings.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])

        let session = sampleCompletedSession()
        container.mainContext.insert(session)

        return container
    }
}
