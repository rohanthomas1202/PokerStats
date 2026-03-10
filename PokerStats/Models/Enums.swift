import Foundation

// MARK: - Game Type

enum GameType: String, Codable, CaseIterable, Identifiable {
    case cash
    case tournament
    case sitAndGo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cash: "Cash Game"
        case .tournament: "Tournament"
        case .sitAndGo: "Sit & Go"
        }
    }
}

// MARK: - Session Status

enum SessionStatus: String, Codable {
    case active
    case completed
}

// MARK: - Preflop Action

enum PreflopAction: String, Codable, CaseIterable {
    case fold
    case call
    case raise

    var displayName: String {
        switch self {
        case .fold: "Fold"
        case .call: "Call"
        case .raise: "Raise"
        }
    }

    var shortName: String {
        switch self {
        case .fold: "F"
        case .call: "C"
        case .raise: "R"
        }
    }
}

// MARK: - Three-Bet Response

enum ThreeBetResponse: String, Codable {
    case folded
    case called
    case fourBetPlus

    var displayName: String {
        switch self {
        case .folded: "Folded"
        case .called: "Called"
        case .fourBetPlus: "4-Bet+"
        }
    }
}

// MARK: - Postflop Result

enum PostflopResult: String, Codable, CaseIterable {
    case wonPreflop
    case wonBeforeShowdown
    case lostBeforeShowdown
    case wonAtShowdown
    case lostAtShowdown

    var displayName: String {
        switch self {
        case .wonPreflop: "Won Preflop"
        case .wonBeforeShowdown: "Won Before Showdown"
        case .lostBeforeShowdown: "Lost Before Showdown"
        case .wonAtShowdown: "Won at Showdown"
        case .lostAtShowdown: "Lost at Showdown"
        }
    }

    var shortName: String {
        switch self {
        case .wonPreflop: "Won PF"
        case .wonBeforeShowdown: "Won"
        case .lostBeforeShowdown: "Lost"
        case .wonAtShowdown: "Won SD"
        case .lostAtShowdown: "Lost SD"
        }
    }

    var isWin: Bool {
        switch self {
        case .wonPreflop, .wonBeforeShowdown, .wonAtShowdown: true
        case .lostBeforeShowdown, .lostAtShowdown: false
        }
    }

    var isShowdown: Bool {
        self == .wonAtShowdown || self == .lostAtShowdown
    }

    var sawFlop: Bool {
        self != .wonPreflop
    }
}

// MARK: - Seat Position

enum SeatPosition: String, Codable, CaseIterable {
    case sb = "SB"
    case bb = "BB"
    case utg = "UTG"
    case mp = "MP"
    case co = "CO"
    case btn = "BTN"
    case unknown = "?"

    var displayName: String {
        rawValue
    }
}

// MARK: - Common Stakes

enum CommonStakes: String, CaseIterable, Identifiable {
    case oneTwo = "1/2"
    case oneThree = "1/3"
    case twoFive = "2/5"
    case fiveTen = "5/10"
    case tenTwenty = "10/20"
    case custom = "Custom"

    var id: String { rawValue }
}
