import Foundation

struct TableSeat: Codable, Identifiable, Equatable {
    let index: Int
    var playerName: String
    var isOccupied: Bool
    var id: Int { index }

    var displayName: String {
        playerName.isEmpty ? "Seat \(index + 1)" : playerName
    }
}

struct TableConfig: Codable, Equatable {
    var seats: [TableSeat]
    var heroSeatIndex: Int
    var buttonSeatIndex: Int // -1 = not yet calibrated (awaiting first hand)

    /// Number of currently occupied seats.
    var activePlayerCount: Int {
        seats.filter(\.isOccupied).count
    }

    /// All seat indices that are currently occupied, in clockwise order.
    var occupiedSeatIndices: [Int] {
        seats.filter(\.isOccupied).map(\.index).sorted()
    }

    /// Whether the button position has been calibrated from the first hand.
    var isCalibrated: Bool {
        buttonSeatIndex >= 0
    }
}
