import Foundation
import SwiftData

@Model
final class Session {
    var id: UUID
    var startTime: Date
    var endTime: Date?
    var location: String
    var gameType: GameType
    var stakes: String
    var notes: String
    var statusRaw: String

    @Transient
    var status: SessionStatus {
        get { SessionStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    // Money tracking (inline on session)
    var buyIn: Double
    var rebuys: Double
    var addOns: Double
    var cashOut: Double
    var tipRake: Double

    // Mental state tracking (1-5 scale, nil if not recorded)
    var tiltLevel: Int?
    var energyLevel: Int?
    var focusLevel: Int?

    // Table configuration for auto position tracking (nil = disabled)
    var tableConfigData: Data?

    @Transient
    var tableConfig: TableConfig? {
        get {
            guard let data = tableConfigData else { return nil }
            return try? JSONDecoder().decode(TableConfig.self, from: data)
        }
        set {
            tableConfigData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }

    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \Hand.session)
    var hands: [Hand]

    // MARK: - Computed Properties

    var totalInvested: Double {
        buyIn + rebuys + addOns
    }

    var netProfit: Double {
        cashOut - totalInvested
    }

    var duration: TimeInterval {
        (endTime ?? .now).timeIntervalSince(startTime)
    }

    var durationHours: Double {
        duration / 3600.0
    }

    var hourlyRate: Double? {
        guard durationHours > 0.01 else { return nil }
        return netProfit / durationHours
    }

    var roi: Double? {
        guard totalInvested > 0 else { return nil }
        return netProfit / totalInvested
    }

    var isActive: Bool {
        status == .active
    }

    var handCount: Int {
        hands.count
    }

    var nextHandNumber: Int {
        (hands.map(\.handNumber).max() ?? 0) + 1
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        startTime: Date = .now,
        endTime: Date? = nil,
        location: String = "",
        gameType: GameType = .cash,
        stakes: String = "1/2",
        notes: String = "",
        status: SessionStatus = .active,
        buyIn: Double = 0,
        rebuys: Double = 0,
        addOns: Double = 0,
        cashOut: Double = 0,
        tipRake: Double = 0
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.location = location
        self.gameType = gameType
        self.stakes = stakes
        self.notes = notes
        self.statusRaw = status.rawValue
        self.buyIn = buyIn
        self.rebuys = rebuys
        self.addOns = addOns
        self.cashOut = cashOut
        self.tipRake = tipRake
        self.hands = []
    }
}
