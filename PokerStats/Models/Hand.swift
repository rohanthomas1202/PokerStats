import Foundation
import SwiftData

@Model
final class Hand {
    var id: UUID
    var session: Session?
    var handNumber: Int
    var timestamp: Date

    // Preflop
    var preflopAction: PreflopAction
    var faced3Bet: Bool
    var threeBetResponse: ThreeBetResponse?

    // Postflop
    var postflopResult: PostflopResult?
    var didCBet: Bool?

    // Metadata
    var notes: String
    var position: SeatPosition

    // MARK: - Computed Stat Flags

    /// True if player voluntarily put money in pot preflop (call or raise).
    /// Posting blinds does NOT count.
    var voluntarilyPutMoneyIn: Bool {
        preflopAction == .call || preflopAction == .raise
    }

    /// True if player raised preflop (open-raise, 3-bet, 4-bet all count).
    var raisedPreflop: Bool {
        preflopAction == .raise
    }

    /// True if player folded preflop (either initial fold or fold to 3-bet).
    var foldedPreflop: Bool {
        if preflopAction == .fold { return true }
        if faced3Bet && threeBetResponse == .folded { return true }
        return false
    }

    /// True if player saw the flop (postflop result exists and isn't wonPreflop).
    var sawFlop: Bool {
        guard let result = postflopResult else { return false }
        return result.sawFlop
    }

    /// True if hand reached showdown with player still in.
    var wentToShowdown: Bool {
        guard let result = postflopResult else { return false }
        return result.isShowdown
    }

    /// True if player won at showdown.
    var wonAtShowdown: Bool {
        postflopResult == .wonAtShowdown
    }

    /// True if player won the hand (any win condition).
    var wonHand: Bool {
        guard let result = postflopResult else { return false }
        return result.isWin
    }

    /// True if player had an opportunity to c-bet (was preflop raiser and saw flop).
    var hadCBetOpportunity: Bool {
        raisedPreflop && sawFlop
    }

    /// Summary string for display in hand history.
    var actionSummary: String {
        if preflopAction == .fold {
            return "Folded preflop"
        }

        var parts: [String] = []
        parts.append(preflopAction == .raise ? "Raised" : "Called")

        if faced3Bet {
            if let response = threeBetResponse {
                parts.append("faced 3-bet, \(response.displayName.lowercased())")
            }
        }

        if let result = postflopResult {
            parts.append(result.shortName)
        }

        return parts.joined(separator: ", ")
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        handNumber: Int = 1,
        timestamp: Date = .now,
        preflopAction: PreflopAction = .fold,
        faced3Bet: Bool = false,
        threeBetResponse: ThreeBetResponse? = nil,
        postflopResult: PostflopResult? = nil,
        didCBet: Bool? = nil,
        notes: String = "",
        position: SeatPosition = .unknown
    ) {
        self.id = id
        self.handNumber = handNumber
        self.timestamp = timestamp
        self.preflopAction = preflopAction
        self.faced3Bet = faced3Bet
        self.threeBetResponse = threeBetResponse
        self.postflopResult = postflopResult
        self.didCBet = didCBet
        self.notes = notes
        self.position = position
    }
}
