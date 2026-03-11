import Foundation

/// Pure-function service for automatic position tracking.
/// Computes hero's position based on table geometry and button rotation.
enum PositionTracker {

    /// Create an initial table config for a given number of seats.
    /// Hero defaults to seat 0. Button is uncalibrated (-1).
    static func createConfig(totalSeats: Int, heroSeat: Int = 0) -> TableConfig {
        let clamped = max(2, min(9, totalSeats))
        let seats = (0..<clamped).map { index in
            TableSeat(index: index, playerName: "", isOccupied: true)
        }
        return TableConfig(
            seats: seats,
            heroSeatIndex: heroSeat,
            buttonSeatIndex: -1
        )
    }

    /// Compute hero's current SeatPosition given the table config.
    /// Returns `.unknown` if the config is not calibrated or hero seat is empty.
    static func heroPosition(config: TableConfig) -> SeatPosition {
        guard config.isCalibrated else { return .unknown }

        let occupied = config.occupiedSeatIndices
        guard occupied.contains(config.heroSeatIndex),
              occupied.contains(config.buttonSeatIndex) else {
            return .unknown
        }

        let positions = SeatPosition.positions(forTableSize: occupied.count)
        guard positions.count == occupied.count else { return .unknown }

        // Find the button's index in the occupied seats list
        guard let buttonOccupiedIdx = occupied.firstIndex(of: config.buttonSeatIndex) else {
            return .unknown
        }
        // Find hero's index in the occupied seats list
        guard let heroOccupiedIdx = occupied.firstIndex(of: config.heroSeatIndex) else {
            return .unknown
        }

        // Hero's distance from button in the occupied seats (clockwise)
        let distance = (heroOccupiedIdx - buttonOccupiedIdx + occupied.count) % occupied.count

        return positions[distance]
    }

    /// Advance the button one seat clockwise (skipping empty seats).
    static func advanceButton(config: TableConfig) -> TableConfig {
        var updated = config
        let occupied = config.occupiedSeatIndices
        guard occupied.count >= 2 else { return config }

        if let currentIdx = occupied.firstIndex(of: config.buttonSeatIndex) {
            let nextIdx = (currentIdx + 1) % occupied.count
            updated.buttonSeatIndex = occupied[nextIdx]
        } else {
            // Button is on an empty seat; move to the next occupied seat clockwise
            let totalSeats = config.seats.count
            for offset in 1...totalSeats {
                let candidateSeat = (config.buttonSeatIndex + offset) % totalSeats
                if occupied.contains(candidateSeat) {
                    updated.buttonSeatIndex = candidateSeat
                    break
                }
            }
        }

        return updated
    }

    /// Infer which seat has the button, given hero's seat and position on the first hand.
    /// This reverse-computes the button location from the hero's known position.
    static func inferButtonSeat(heroSeat: Int, heroPosition: SeatPosition, config: TableConfig) -> Int {
        let occupied = config.occupiedSeatIndices
        let positions = SeatPosition.positions(forTableSize: occupied.count)

        // Find hero's distance from the button for the given position
        guard let distanceFromButton = positions.firstIndex(of: heroPosition) else {
            // Unknown position — can't infer, default button to first occupied seat
            return occupied.first ?? 0
        }

        // Hero is at `distanceFromButton` seats clockwise from the button
        guard let heroOccupiedIdx = occupied.firstIndex(of: heroSeat) else {
            return occupied.first ?? 0
        }

        // Button occupied index = hero occupied index - distance (mod count)
        let buttonOccupiedIdx = (heroOccupiedIdx - distanceFromButton + occupied.count) % occupied.count
        return occupied[buttonOccupiedIdx]
    }

    /// Add a player to a specific seat index. Returns updated config.
    static func addPlayer(at seatIndex: Int, name: String = "", config: TableConfig) -> TableConfig {
        var updated = config
        guard seatIndex >= 0, seatIndex < updated.seats.count else { return config }
        updated.seats[seatIndex].isOccupied = true
        updated.seats[seatIndex].playerName = name
        return updated
    }

    /// Remove a player from a specific seat. Returns updated config.
    /// Cannot remove the hero's seat.
    static func removePlayer(at seatIndex: Int, config: TableConfig) -> TableConfig {
        var updated = config
        guard seatIndex >= 0,
              seatIndex < updated.seats.count,
              seatIndex != config.heroSeatIndex else { return config }
        updated.seats[seatIndex].isOccupied = false
        updated.seats[seatIndex].playerName = ""
        return updated
    }

    /// Add a new seat to the table (player joins, table grows).
    static func addSeat(name: String = "", config: TableConfig) -> TableConfig {
        var updated = config
        let newIndex = updated.seats.count
        guard newIndex < 9 else { return config } // max 9 seats
        updated.seats.append(TableSeat(index: newIndex, playerName: name, isOccupied: true))
        return updated
    }

    /// Remove the last empty seat from the table (shrink table).
    static func removeSeat(config: TableConfig) -> TableConfig {
        var updated = config
        guard updated.seats.count > 2 else { return config } // min 2 seats
        // Only remove the last seat if it's not hero's seat and not the button
        let lastIndex = updated.seats.count - 1
        guard lastIndex != config.heroSeatIndex,
              lastIndex != config.buttonSeatIndex else { return config }
        updated.seats.removeLast()
        return updated
    }
}
