import Foundation
import Observation
import UIKit

/// State machine for the multi-step hand logging flow.
/// Designed for sub-3-second hand entry.
@Observable
@MainActor
final class HandLoggerViewModel {
    // Current step in the flow
    var currentStep: LoggerStep = .position

    // Captured data
    var selectedPosition: SeatPosition = .unknown
    var preflopAction: PreflopAction?
    var faced3Bet: Bool = false
    var threeBetResponse: ThreeBetResponse?
    var postflopResult: PostflopResult?
    var didCBet: Bool?
    var notes: String = ""

    // UI state
    var showNoteField: Bool = false

    // Auto-position tracking
    var autoPosition: SeatPosition?
    var isOverridingPosition: Bool = false
    var tablePlayerCount: Int?

    var isAutoPositionMode: Bool {
        autoPosition != nil
    }

    /// Positions available for selection, filtered by table size if known.
    var availablePositions: [SeatPosition] {
        if let count = tablePlayerCount {
            return SeatPosition.positions(forTableSize: count)
        }
        return SeatPosition.allPlayable
    }

    enum LoggerStep: Equatable {
        case position               // "Your Position"
        case preflop
        case threeBetQualifier      // "Faced a re-raise?"
        case threeBetResponse       // "Your response?" (fold/call/4bet)
        case postflopResult         // "How did the hand end?"
        case cBet                   // "Did you c-bet?"
        case done
    }

    // MARK: - Auto Position

    func configureAutoPosition(_ position: SeatPosition, playerCount: Int? = nil) {
        autoPosition = position
        selectedPosition = position
        tablePlayerCount = playerCount
        currentStep = .preflop
    }

    func overridePosition() {
        isOverridingPosition = true
    }

    func confirmOverride(_ position: SeatPosition) {
        selectedPosition = position
        isOverridingPosition = false
    }

    // MARK: - Step 0: Position

    func selectPosition(_ position: SeatPosition) {
        selectedPosition = position
        hapticFeedback()
        currentStep = .preflop
    }

    // MARK: - Step 1: Preflop Action

    func selectPreflopAction(_ action: PreflopAction) {
        preflopAction = action
        hapticFeedback()

        switch action {
        case .fold:
            // Fold = done immediately (1 tap)
            currentStep = .done

        case .call:
            // Call → go to postflop result
            currentStep = .postflopResult

        case .raise:
            // Raise → ask about 3-bet
            currentStep = .threeBetQualifier
        }
    }

    // MARK: - Step 1b: 3-Bet Qualifier

    func selectFaced3Bet(_ faced: Bool) {
        faced3Bet = faced
        hapticFeedback()

        if faced {
            currentStep = .threeBetResponse
        } else {
            // No 3-bet → go to postflop
            currentStep = .postflopResult
        }
    }

    // MARK: - Step 1c: 3-Bet Response

    func selectThreeBetResponse(_ response: ThreeBetResponse) {
        threeBetResponse = response
        hapticFeedback()

        switch response {
        case .folded:
            // Folded to 3-bet = done
            currentStep = .done
        case .called, .fourBetPlus:
            // Still in hand → postflop
            currentStep = .postflopResult
        }
    }

    // MARK: - Step 2: Postflop Result

    func selectPostflopResult(_ result: PostflopResult) {
        postflopResult = result
        hapticFeedback()

        // If hero was the raiser and saw the flop → ask about c-bet
        if preflopAction == .raise && result.sawFlop {
            currentStep = .cBet
        } else {
            currentStep = .done
        }
    }

    // MARK: - Step 2b: C-Bet

    func selectCBet(_ did: Bool) {
        didCBet = did
        hapticFeedback()
        currentStep = .done
    }

    // MARK: - Navigation

    func goBack() {
        switch currentStep {
        case .position:
            break // Can't go back from first step
        case .preflop:
            if isAutoPositionMode {
                // In auto mode, "back" from preflop opens the position override
                overridePosition()
                return
            }
            selectedPosition = .unknown
            currentStep = .position
        case .threeBetQualifier:
            preflopAction = nil
            currentStep = .preflop
        case .threeBetResponse:
            faced3Bet = false
            currentStep = .threeBetQualifier
        case .postflopResult:
            if preflopAction == .raise {
                if faced3Bet {
                    threeBetResponse = nil
                    currentStep = .threeBetResponse
                } else {
                    currentStep = .threeBetQualifier
                }
            } else {
                preflopAction = nil
                currentStep = .preflop
            }
        case .cBet:
            postflopResult = nil
            currentStep = .postflopResult
        case .done:
            break
        }
    }

    var canGoBack: Bool {
        if isAutoPositionMode {
            return currentStep != .preflop && currentStep != .done
        }
        return currentStep != .position && currentStep != .done
    }

    // MARK: - Build Hand

    var isDone: Bool {
        currentStep == .done
    }

    func buildHand() -> Hand {
        Hand(
            preflopAction: preflopAction ?? .fold,
            faced3Bet: faced3Bet,
            threeBetResponse: threeBetResponse,
            postflopResult: preflopAction == .fold ? nil : postflopResult,
            didCBet: didCBet,
            notes: notes,
            position: selectedPosition
        )
    }

    // MARK: - Reset

    func reset() {
        currentStep = .position
        selectedPosition = .unknown
        preflopAction = nil
        faced3Bet = false
        threeBetResponse = nil
        postflopResult = nil
        didCBet = nil
        notes = ""
        showNoteField = false
        autoPosition = nil
        isOverridingPosition = false
        tablePlayerCount = nil
    }

    // MARK: - Haptics

    private func hapticFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
}
