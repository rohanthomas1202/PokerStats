import Foundation
import SwiftData
@testable import PokerStats

/// Test helper to create in-memory SwiftData containers.
enum TestHelpers {

    @MainActor
    static func createContainer() throws -> ModelContainer {
        let schema = Schema([Session.self, Hand.self, Settings.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Hand Factories

    /// Create a folded hand.
    static func foldHand(number: Int = 1, position: SeatPosition = .unknown) -> Hand {
        Hand(handNumber: number, preflopAction: .fold, position: position)
    }

    /// Create a hand where player called preflop and saw showdown.
    static func callShowdownHand(number: Int = 1, won: Bool, position: SeatPosition = .unknown) -> Hand {
        Hand(
            handNumber: number,
            preflopAction: .call,
            postflopResult: won ? .wonAtShowdown : .lostAtShowdown,
            position: position
        )
    }

    /// Create a hand where player raised preflop, saw flop, and c-bet.
    static func raiseWithCBetHand(number: Int = 1, cBet: Bool, result: PostflopResult, position: SeatPosition = .unknown) -> Hand {
        Hand(
            handNumber: number,
            preflopAction: .raise,
            postflopResult: result,
            didCBet: cBet,
            position: position
        )
    }

    /// Create a hand where player raised and faced a 3-bet.
    static func raiseFaced3BetHand(number: Int = 1, response: ThreeBetResponse, result: PostflopResult? = nil, position: SeatPosition = .unknown) -> Hand {
        var postflop: PostflopResult? = result
        if response == .folded {
            postflop = nil
        }
        return Hand(
            handNumber: number,
            preflopAction: .raise,
            faced3Bet: true,
            threeBetResponse: response,
            postflopResult: postflop,
            position: position
        )
    }

    /// Create a hand where player raised and won preflop.
    static func raiseWonPreflopHand(number: Int = 1, position: SeatPosition = .unknown) -> Hand {
        Hand(
            handNumber: number,
            preflopAction: .raise,
            postflopResult: .wonPreflop,
            position: position
        )
    }

    /// Create a hand where player called and won before showdown.
    static func callWonBeforeShowdownHand(number: Int = 1, position: SeatPosition = .unknown) -> Hand {
        Hand(
            handNumber: number,
            preflopAction: .call,
            postflopResult: .wonBeforeShowdown,
            position: position
        )
    }

    /// Create a raise hand at a specific position.
    static func raiseFromPosition(_ position: SeatPosition, number: Int = 1, result: PostflopResult = .wonPreflop) -> Hand {
        Hand(
            handNumber: number,
            preflopAction: .raise,
            postflopResult: result,
            position: position
        )
    }

    // MARK: - Session Factories

    static func completedSession(
        buyIn: Double = 200,
        cashOut: Double = 300,
        rebuys: Double = 0,
        hours: Double = 2,
        hands: [Hand] = []
    ) -> Session {
        let session = Session(
            startTime: Date(timeIntervalSinceNow: -hours * 3600),
            endTime: .now,
            gameType: .cash,
            stakes: "1/2",
            status: .completed,
            buyIn: buyIn,
            rebuys: rebuys,
            cashOut: cashOut
        )
        for hand in hands {
            hand.session = session
            session.hands.append(hand)
        }
        return session
    }
}
