import Testing
@testable import PokerStats

@Suite("Position Stats Tests")
struct PositionStatsTests {

    // MARK: - statsByPosition

    @Test("Empty hands returns empty position stats")
    func emptyHands() {
        let result = StatCalculator.statsByPosition(hands: [])
        #expect(result.isEmpty)
    }

    @Test("Unknown position hands are excluded from position stats")
    func unknownExcluded() {
        let hands = [
            TestHelpers.foldHand(number: 1),
            TestHelpers.raiseWonPreflopHand(number: 2),
        ]
        let result = StatCalculator.statsByPosition(hands: hands)
        #expect(result.isEmpty)
    }

    @Test("5 BTN hands with 4 raises = 80% PFR on BTN")
    func btnPfrWorkedExample() {
        let hands: [Hand] = [
            TestHelpers.raiseFromPosition(.btn, number: 1, result: .wonPreflop),
            TestHelpers.raiseFromPosition(.btn, number: 2, result: .wonAtShowdown),
            TestHelpers.raiseFromPosition(.btn, number: 3, result: .lostAtShowdown),
            TestHelpers.raiseFromPosition(.btn, number: 4, result: .wonBeforeShowdown),
            TestHelpers.foldHand(number: 5, position: .btn),
        ]

        let result = StatCalculator.statsByPosition(hands: hands)
        #expect(result.count == 1)

        let btnStats = result.first!
        #expect(btnStats.position == .btn)
        #expect(btnStats.handCount == 5)

        // 4 raises out of 5 = 0.8
        let pfr = try! #require(btnStats.pfr)
        #expect(abs(pfr - 0.8) < 0.001)

        // 4 raises + 0 calls = 4 VPIP out of 5 = 0.8
        let vpip = try! #require(btnStats.vpip)
        #expect(abs(vpip - 0.8) < 0.001)
    }

    @Test("Multiple positions return sorted stats")
    func multiplePositions() {
        let hands: [Hand] = [
            TestHelpers.raiseFromPosition(.btn, number: 1),
            TestHelpers.raiseFromPosition(.btn, number: 2),
            TestHelpers.foldHand(number: 3, position: .sb),
            TestHelpers.callShowdownHand(number: 4, won: true, position: .co),
        ]

        let result = StatCalculator.statsByPosition(hands: hands)
        #expect(result.count == 3)

        // Should be in sort order: SB, CO, BTN
        #expect(result[0].position == .sb)
        #expect(result[1].position == .co)
        #expect(result[2].position == .btn)
    }

    // MARK: - vpip(hands:position:)

    @Test("VPIP filtered by position")
    func vpipByPosition() {
        let hands: [Hand] = [
            TestHelpers.raiseFromPosition(.btn, number: 1),
            TestHelpers.foldHand(number: 2, position: .btn),
            TestHelpers.raiseFromPosition(.co, number: 3),
        ]

        // BTN: 1 raise out of 2 = 50%
        let btnVpip = StatCalculator.vpip(hands: hands, position: .btn)
        #expect(btnVpip != nil)
        #expect(abs(btnVpip! - 0.5) < 0.001)

        // CO: 1 raise out of 1 = 100%
        let coVpip = StatCalculator.vpip(hands: hands, position: .co)
        #expect(coVpip != nil)
        #expect(abs(coVpip! - 1.0) < 0.001)

        // UTG: no hands = nil
        let utgVpip = StatCalculator.vpip(hands: hands, position: .utg)
        #expect(utgVpip == nil)
    }

    // MARK: - pfr(hands:position:)

    @Test("PFR filtered by position")
    func pfrByPosition() {
        let hands: [Hand] = [
            TestHelpers.raiseFromPosition(.btn, number: 1),
            TestHelpers.callShowdownHand(number: 2, won: false, position: .btn),
            TestHelpers.foldHand(number: 3, position: .btn),
        ]

        // BTN: 1 raise out of 3 = 33.3%
        let btnPfr = StatCalculator.pfr(hands: hands, position: .btn)
        #expect(btnPfr != nil)
        #expect(abs(btnPfr! - 1.0/3.0) < 0.001)
    }

    // MARK: - Mixed position and unknown

    @Test("Position stats ignore unknown hands in breakdown but include them in global")
    func mixedPositionAndUnknown() {
        let hands: [Hand] = [
            TestHelpers.raiseFromPosition(.btn, number: 1),
            TestHelpers.foldHand(number: 2), // unknown position
            TestHelpers.callShowdownHand(number: 3, won: true, position: .co),
        ]

        let posStats = StatCalculator.statsByPosition(hands: hands)
        #expect(posStats.count == 2) // BTN and CO only

        // Global vpip still counts all 3 hands
        let globalVpip = StatCalculator.vpip(hands: hands)
        #expect(globalVpip != nil)
        // 2 VPIP (raise + call) out of 3 = 66.7%
        #expect(abs(globalVpip! - 2.0/3.0) < 0.001)
    }
}
