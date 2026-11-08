import Testing
@testable import PokerStats

@Suite("Hand Logger Step Sequences")
@MainActor
struct HandLoggerViewModelTests {
    @Test("Fold keeps its two/three-tap path", arguments: [true, false])
    func fold(autoPosition: Bool) {
        let hand = logHand(
            autoPosition: autoPosition,
            steps: [.preflop, .done],
            actions: [{ $0.selectPreflopAction(.fold) }],
            taps: autoPosition ? 2 : 3
        )
        #expect(hand.preflopAction == .fold)
        #expect(hand.postflopResult == nil)
    }

    @Test("Call and result keep their three/four-tap path", arguments: [true, false])
    func call(autoPosition: Bool) {
        let hand = logHand(
            autoPosition: autoPosition,
            steps: [.preflop, .postflopResult, .done],
            actions: [
                { $0.selectPreflopAction(.call) },
                { $0.selectPostflopResult(.wonAtShowdown) }
            ],
            taps: autoPosition ? 3 : 4
        )
        #expect(hand.preflopAction == .call)
        #expect(hand.postflopResult == .wonAtShowdown)
        #expect(hand.didCBet == nil)
    }

    @Test("Raise to flop keeps its five/six-tap path", arguments: [true, false])
    func raiseToFlop(autoPosition: Bool) {
        let hand = logHand(
            autoPosition: autoPosition,
            steps: [.preflop, .threeBetQualifier, .postflopResult, .cBet, .done],
            actions: [
                { $0.selectPreflopAction(.raise) },
                { $0.selectFaced3Bet(false) },
                { $0.selectPostflopResult(.wonBeforeShowdown) },
                { $0.selectCBet(true) }
            ],
            taps: autoPosition ? 5 : 6
        )
        #expect(hand.preflopAction == .raise)
        #expect(!hand.faced3Bet)
        #expect(hand.postflopResult == .wonBeforeShowdown)
        #expect(hand.didCBet == true)
    }

    @Test("Raise then call a 3-bet keeps its six/seven-tap path", arguments: [true, false])
    func raiseThenThreeBet(autoPosition: Bool) {
        let hand = logHand(
            autoPosition: autoPosition,
            steps: [.preflop, .threeBetQualifier, .threeBetResponse, .postflopResult, .cBet, .done],
            actions: [
                { $0.selectPreflopAction(.raise) },
                { $0.selectFaced3Bet(true) },
                { $0.selectThreeBetResponse(.called) },
                { $0.selectPostflopResult(.lostAtShowdown) },
                { $0.selectCBet(false) }
            ],
            taps: autoPosition ? 6 : 7
        )
        #expect(hand.preflopAction == .raise)
        #expect(hand.faced3Bet)
        #expect(hand.threeBetResponse == .called)
        #expect(hand.postflopResult == .lostAtShowdown)
        #expect(hand.didCBet == false)
    }

    private func logHand(
        autoPosition: Bool,
        steps expectedSteps: [HandLoggerViewModel.LoggerStep],
        actions: [@MainActor (HandLoggerViewModel) -> Void],
        taps: Int
    ) -> Hand {
        let vm = HandLoggerViewModel()
        #expect(vm.currentStep == .position)
        if autoPosition {
            vm.configureAutoPosition(.btn)
        }
        // Opening the sheet is the first tap. Every transition below is one button tap.
        var steps = [vm.currentStep]
        if !autoPosition {
            vm.selectPosition(.btn)
            steps.append(vm.currentStep)
        }
        for action in actions {
            #expect(!vm.isDone)
            action(vm)
            steps.append(vm.currentStep)
        }
        let prefix: [HandLoggerViewModel.LoggerStep] = autoPosition ? [] : [.position]
        #expect(steps == prefix + expectedSteps)
        #expect(steps.count == taps)
        #expect(vm.isDone)
        let hand = vm.buildHand()
        #expect(hand.position == .btn)
        return hand
    }
}
