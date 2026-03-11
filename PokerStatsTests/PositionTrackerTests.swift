import Testing
@testable import PokerStats

@Suite("Position Tracker Tests")
struct PositionTrackerTests {

    // MARK: - positions(forTableSize:)

    @Test("6-max returns correct positions")
    func sixMaxPositions() {
        let positions = SeatPosition.positions(forTableSize: 6)
        #expect(positions == [.btn, .sb, .bb, .utg, .mp, .co])
    }

    @Test("9-max returns correct positions")
    func nineMaxPositions() {
        let positions = SeatPosition.positions(forTableSize: 9)
        #expect(positions == [.btn, .sb, .bb, .utg, .utg1, .mp, .lj, .hj, .co])
    }

    @Test("Heads-up returns BTN and BB")
    func headsUpPositions() {
        let positions = SeatPosition.positions(forTableSize: 2)
        #expect(positions == [.btn, .bb])
    }

    @Test("All table sizes 2-9 return correct number of positions")
    func allTableSizesCount() {
        for size in 2...9 {
            let positions = SeatPosition.positions(forTableSize: size)
            #expect(positions.count == size, "Table size \(size) should return \(size) positions")
        }
    }

    // MARK: - createConfig

    @Test("createConfig creates correct initial state")
    func createConfig() {
        let config = PositionTracker.createConfig(totalSeats: 6)
        #expect(config.seats.count == 6)
        #expect(config.heroSeatIndex == 0)
        #expect(config.buttonSeatIndex == -1)
        #expect(!config.isCalibrated)
        #expect(config.activePlayerCount == 6)
        #expect(config.seats.allSatisfy { $0.isOccupied })
    }

    @Test("createConfig clamps to valid range")
    func createConfigClamps() {
        let tooSmall = PositionTracker.createConfig(totalSeats: 1)
        #expect(tooSmall.seats.count == 2)

        let tooLarge = PositionTracker.createConfig(totalSeats: 15)
        #expect(tooLarge.seats.count == 9)
    }

    // MARK: - heroPosition

    @Test("Hero position when hero is on the button")
    func heroOnButton() {
        let config = TableConfig(
            seats: makeSeats(count: 6),
            heroSeatIndex: 0,
            buttonSeatIndex: 0
        )
        let position = PositionTracker.heroPosition(config: config)
        #expect(position == .btn)
    }

    @Test("Hero position when hero is 2 seats from button (BB)")
    func heroAsBB() {
        // 6-max, button on seat 0, hero on seat 2 → distance 2 → BB
        let config = TableConfig(
            seats: makeSeats(count: 6),
            heroSeatIndex: 2,
            buttonSeatIndex: 0
        )
        let position = PositionTracker.heroPosition(config: config)
        #expect(position == .bb)
    }

    @Test("Hero position UTG at 6-max")
    func heroAsUTG() {
        // 6-max, button on seat 0, hero on seat 3 → distance 3 → UTG
        let config = TableConfig(
            seats: makeSeats(count: 6),
            heroSeatIndex: 3,
            buttonSeatIndex: 0
        )
        let position = PositionTracker.heroPosition(config: config)
        #expect(position == .utg)
    }

    @Test("Hero position with uncalibrated config returns unknown")
    func uncalibratedReturnsUnknown() {
        let config = TableConfig(
            seats: makeSeats(count: 6),
            heroSeatIndex: 0,
            buttonSeatIndex: -1
        )
        let position = PositionTracker.heroPosition(config: config)
        #expect(position == .unknown)
    }

    // MARK: - advanceButton

    @Test("Button advances clockwise through all seats")
    func buttonAdvancesClockwise() {
        var config = TableConfig(
            seats: makeSeats(count: 6),
            heroSeatIndex: 0,
            buttonSeatIndex: 0
        )
        config = PositionTracker.advanceButton(config: config)
        #expect(config.buttonSeatIndex == 1)

        config = PositionTracker.advanceButton(config: config)
        #expect(config.buttonSeatIndex == 2)
    }

    @Test("Button wraps around from last seat to first")
    func buttonWrapsAround() {
        var config = TableConfig(
            seats: makeSeats(count: 6),
            heroSeatIndex: 0,
            buttonSeatIndex: 5
        )
        config = PositionTracker.advanceButton(config: config)
        #expect(config.buttonSeatIndex == 0)
    }

    @Test("Button skips empty seats")
    func buttonSkipsEmptySeats() {
        var seats = makeSeats(count: 6)
        seats[1].isOccupied = false // seat 1 is empty
        let config = TableConfig(
            seats: seats,
            heroSeatIndex: 0,
            buttonSeatIndex: 0
        )
        let advanced = PositionTracker.advanceButton(config: config)
        #expect(advanced.buttonSeatIndex == 2) // skipped seat 1
    }

    // MARK: - Full orbit rotation

    @Test("Full 6-max orbit cycles through all positions")
    func fullOrbitSixMax() {
        // Hero at seat 0, button starts at seat 0 (hero = BTN)
        var config = TableConfig(
            seats: makeSeats(count: 6),
            heroSeatIndex: 0,
            buttonSeatIndex: 0
        )

        // Positions in a full orbit as button advances:
        // BTN → CO → MP → UTG → BB → SB → BTN
        let expectedPositions: [SeatPosition] = [.btn, .co, .mp, .utg, .bb, .sb]

        for (hand, expected) in expectedPositions.enumerated() {
            let position = PositionTracker.heroPosition(config: config)
            #expect(position == expected, "Hand \(hand + 1): expected \(expected), got \(position)")
            config = PositionTracker.advanceButton(config: config)
        }

        // After full orbit, should be back to BTN
        let finalPosition = PositionTracker.heroPosition(config: config)
        #expect(finalPosition == .btn)
    }

    // MARK: - inferButtonSeat

    @Test("Infer button seat when hero is BTN")
    func inferButtonWhenHeroIsBTN() {
        let config = TableConfig(
            seats: makeSeats(count: 6),
            heroSeatIndex: 0,
            buttonSeatIndex: -1
        )
        let buttonSeat = PositionTracker.inferButtonSeat(
            heroSeat: 0, heroPosition: .btn, config: config
        )
        #expect(buttonSeat == 0)
    }

    @Test("Infer button seat when hero is BB")
    func inferButtonWhenHeroIsBB() {
        // 6-max, hero at seat 2, hero says they're BB
        // BB = distance 2 from button → button should be at seat 0
        let config = TableConfig(
            seats: makeSeats(count: 6),
            heroSeatIndex: 2,
            buttonSeatIndex: -1
        )
        let buttonSeat = PositionTracker.inferButtonSeat(
            heroSeat: 2, heroPosition: .bb, config: config
        )
        #expect(buttonSeat == 0)
    }

    @Test("Infer button seat when hero is CO")
    func inferButtonWhenHeroIsCO() {
        // 6-max, hero at seat 3, hero says they're CO
        // CO = distance 5 from button → button at seat (3-5+6)%6 = 4
        let config = TableConfig(
            seats: makeSeats(count: 6),
            heroSeatIndex: 3,
            buttonSeatIndex: -1
        )
        let buttonSeat = PositionTracker.inferButtonSeat(
            heroSeat: 3, heroPosition: .co, config: config
        )
        #expect(buttonSeat == 4)

        // Verify by computing hero position with inferred button
        let calibrated = TableConfig(
            seats: makeSeats(count: 6),
            heroSeatIndex: 3,
            buttonSeatIndex: buttonSeat
        )
        #expect(PositionTracker.heroPosition(config: calibrated) == .co)
    }

    // MARK: - Player management

    @Test("Remove player marks seat as unoccupied")
    func removePlayer() {
        let config = PositionTracker.createConfig(totalSeats: 6)
        let updated = PositionTracker.removePlayer(at: 3, config: config)
        #expect(!updated.seats[3].isOccupied)
        #expect(updated.activePlayerCount == 5)
    }

    @Test("Cannot remove hero seat")
    func cannotRemoveHero() {
        let config = PositionTracker.createConfig(totalSeats: 6)
        let updated = PositionTracker.removePlayer(at: 0, config: config) // hero is at 0
        #expect(updated.seats[0].isOccupied) // unchanged
        #expect(updated.activePlayerCount == 6)
    }

    @Test("Add player marks seat as occupied")
    func addPlayer() {
        var config = PositionTracker.createConfig(totalSeats: 6)
        config.seats[3].isOccupied = false
        let updated = PositionTracker.addPlayer(at: 3, name: "Mike", config: config)
        #expect(updated.seats[3].isOccupied)
        #expect(updated.seats[3].playerName == "Mike")
        #expect(updated.activePlayerCount == 6)
    }

    @Test("Position recalculates after player removal")
    func positionAfterRemoval() {
        // 6-max, hero at seat 0, button at seat 0 (hero = BTN)
        var config = TableConfig(
            seats: makeSeats(count: 6),
            heroSeatIndex: 0,
            buttonSeatIndex: 0
        )
        #expect(PositionTracker.heroPosition(config: config) == .btn)

        // Remove seat 3 → now 5 players
        config = PositionTracker.removePlayer(at: 3, config: config)
        // Hero still at seat 0, button still at seat 0
        // 5-max positions: [BTN, SB, BB, UTG, CO]
        // Hero is still BTN (distance 0)
        #expect(PositionTracker.heroPosition(config: config) == .btn)
    }

    // MARK: - Edge cases

    @Test("Heads-up button advancement")
    func headsUpAdvancement() {
        var config = TableConfig(
            seats: makeSeats(count: 2),
            heroSeatIndex: 0,
            buttonSeatIndex: 0
        )
        // Hero is BTN (which is also SB in heads-up)
        #expect(PositionTracker.heroPosition(config: config) == .btn)

        config = PositionTracker.advanceButton(config: config)
        // Hero is now BB
        #expect(PositionTracker.heroPosition(config: config) == .bb)

        config = PositionTracker.advanceButton(config: config)
        // Back to BTN
        #expect(PositionTracker.heroPosition(config: config) == .btn)
    }

    @Test("9-max full orbit")
    func nineMaxOrbit() {
        var config = TableConfig(
            seats: makeSeats(count: 9),
            heroSeatIndex: 0,
            buttonSeatIndex: 0
        )

        let expectedPositions: [SeatPosition] = [.btn, .co, .hj, .lj, .mp, .utg1, .utg, .bb, .sb]

        for (hand, expected) in expectedPositions.enumerated() {
            let position = PositionTracker.heroPosition(config: config)
            #expect(position == expected, "Hand \(hand + 1): expected \(expected), got \(position)")
            config = PositionTracker.advanceButton(config: config)
        }

        // After full orbit, back to BTN
        #expect(PositionTracker.heroPosition(config: config) == .btn)
    }

    // MARK: - Helpers

    private func makeSeats(count: Int) -> [TableSeat] {
        (0..<count).map { TableSeat(index: $0, playerName: "", isOccupied: true) }
    }
}
