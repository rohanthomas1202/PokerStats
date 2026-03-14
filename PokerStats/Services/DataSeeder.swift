import Foundation
import SwiftData

/// Generates realistic test data for 6 months of poker play.
@MainActor
enum DataSeeder {

    static func seed(into context: ModelContext) {
        let calendar = Calendar.current
        let now = Date.now

        // Locations with weighted frequency
        let locations = [
            ("Bellagio", 12), ("Aria", 10), ("Wynn", 8),
            ("Home Game", 7), ("Commerce Casino", 5), ("Venetian", 4),
            ("WSOP", 2), ("Lodge Poker Club", 3), ("Hustler Casino", 3),
        ]

        let sessionNotes = [
            "", "", "", "", // Most sessions have no notes
            "Table was super soft tonight, lots of limpers.",
            "Ran into a cooler set over set, stayed disciplined.",
            "Good session, played tight and picked spots well.",
            "Tough table, two strong regs on my left.",
            "Tilted a bit after a bad beat, need to work on that.",
            "Great read on villain's bluff river, hero called.",
            "Short session, table broke early.",
            "Played too many hands from the blinds.",
            "Hit a massive pot with AA vs KK, lucky timing.",
            "Card dead for 2 hours, then hit a rush.",
            "Focused on position play, felt really good.",
        ]

        // Generate ~50 sessions spread over 6 months
        var sessions: [(session: Session, handCount: Int)] = []

        for weekOffset in 0..<26 { // 26 weeks = ~6 months
            // 1-3 sessions per week, weighted toward 2
            let sessionsThisWeek = weightedRandom([1: 30, 2: 50, 3: 20])

            for _ in 0..<sessionsThisWeek {
                let daysAgo = (25 - weekOffset) * 7 + Int.random(in: 0...6)
                guard let sessionDate = calendar.date(byAdding: .day, value: -daysAgo, to: now) else { continue }

                // Random start time: 12pm-9pm
                let hour = Int.random(in: 12...21)
                let minute = [0, 15, 30, 45].randomElement()!
                var components = calendar.dateComponents([.year, .month, .day], from: sessionDate)
                components.hour = hour
                components.minute = minute
                guard let startTime = calendar.date(from: components) else { continue }

                // Duration: 1.5-8 hours, weighted toward 3-5
                let durationHours = weightedDuration()
                let endTime = startTime.addingTimeInterval(durationHours * 3600)

                // Skip if end time is in the future
                guard endTime < now else { continue }

                // Stakes: mostly 1/2 and 1/3, some 2/5
                let stakes = weightedStakes()
                let buyIn = buyInForStakes(stakes)

                // Rebuys: 30% chance of 1 rebuy, 10% chance of 2
                let rebuyCount = weightedRandom([0: 60, 1: 30, 2: 10])
                let rebuys = Double(rebuyCount) * buyIn

                // Cash out: realistic distribution (slight winner overall)
                let totalInvested = buyIn + rebuys
                let cashOut = generateCashOut(invested: totalInvested, stakes: stakes, hours: durationHours)

                // Location
                let location = weightedLocation(locations)

                // Mental state
                let tilt = weightedMental(low: 60, mid: 25, high: 15) // mostly calm
                let energy = weightedMental(low: 20, mid: 50, high: 30) // mostly mid-high
                let focus = weightedMental(low: 15, mid: 45, high: 40) // mostly mid-high

                let session = Session(
                    startTime: startTime,
                    endTime: endTime,
                    location: location,
                    gameType: .cash,
                    stakes: stakes,
                    notes: sessionNotes.randomElement() ?? "",
                    status: .completed,
                    buyIn: buyIn,
                    rebuys: rebuys,
                    cashOut: cashOut,
                    tipRake: Double(Int.random(in: 5...25))
                )
                session.tiltLevel = tilt
                session.energyLevel = energy
                session.focusLevel = focus

                // Hands per session: ~25-35 per hour
                let handsPerHour = Double.random(in: 22...35)
                let handCount = max(5, Int(durationHours * handsPerHour))

                context.insert(session)
                sessions.append((session, handCount))
            }
        }

        // Generate hands for each session
        let positions6Max: [SeatPosition] = [.btn, .sb, .bb, .utg, .mp, .co]

        for (session, handCount) in sessions {
            let sessionStart = session.startTime
            let sessionDuration = session.endTime?.timeIntervalSince(sessionStart) ?? 14400

            for i in 1...handCount {
                let handTime = sessionStart.addingTimeInterval(sessionDuration * Double(i) / Double(handCount + 1))
                let position = positions6Max[i % 6]

                let hand = generateRealisticHand(
                    handNumber: i,
                    timestamp: handTime,
                    position: position
                )
                hand.session = session
                context.insert(hand)
            }
        }

        try? context.save()
    }

    // MARK: - Hand Generation

    /// Generates a realistic hand for a TAG (tight-aggressive) player.
    /// Target stats: ~24% VPIP, ~18% PFR, ~65% Fold-to-3Bet, ~55% CBet, ~30% WTSD, ~52% W$SD
    private static func generateRealisticHand(
        handNumber: Int,
        timestamp: Date,
        position: SeatPosition
    ) -> Hand {
        // Position-adjusted VPIP/PFR rates
        let (vpipRate, pfrRate) = positionRates(position)

        let roll = Double.random(in: 0...1)

        if roll > vpipRate {
            // FOLD preflop
            return Hand(
                handNumber: handNumber,
                timestamp: timestamp,
                preflopAction: .fold,
                position: position
            )
        }

        // Determine if raise or call
        let isRaise = roll < pfrRate
        let preflopAction: PreflopAction = isRaise ? .raise : .call

        // 3-bet scenario: ~20% of the time when we raise, we face a 3-bet
        let faced3Bet = isRaise && Double.random(in: 0...1) < 0.20
        var threeBetResponse: ThreeBetResponse?

        if faced3Bet {
            let resp = Double.random(in: 0...1)
            if resp < 0.62 {
                threeBetResponse = .folded
                // Folded to 3-bet: hand is over
                return Hand(
                    handNumber: handNumber,
                    timestamp: timestamp,
                    preflopAction: preflopAction,
                    faced3Bet: true,
                    threeBetResponse: .folded,
                    position: position
                )
            } else if resp < 0.90 {
                threeBetResponse = .called
            } else {
                threeBetResponse = .fourBetPlus
            }
        }

        // Postflop result
        let postflopResult = generatePostflopResult(isRaise: isRaise)

        // C-bet: if we raised and saw flop
        var didCBet: Bool?
        if isRaise && postflopResult.sawFlop {
            didCBet = Double.random(in: 0...1) < 0.58
        }

        return Hand(
            handNumber: handNumber,
            timestamp: timestamp,
            preflopAction: preflopAction,
            faced3Bet: faced3Bet,
            threeBetResponse: threeBetResponse,
            postflopResult: postflopResult,
            didCBet: didCBet,
            position: position
        )
    }

    private static func positionRates(_ position: SeatPosition) -> (vpip: Double, pfr: Double) {
        switch position {
        case .btn:  return (0.35, 0.28)
        case .co:   return (0.28, 0.22)
        case .mp:   return (0.20, 0.16)
        case .utg:  return (0.15, 0.12)
        case .sb:   return (0.28, 0.18)
        case .bb:   return (0.26, 0.10)
        default:    return (0.24, 0.18)
        }
    }

    private static func generatePostflopResult(isRaise: Bool) -> PostflopResult {
        let roll = Double.random(in: 0...1)

        if isRaise && roll < 0.30 {
            return .wonPreflop // Won preflop with aggression
        }

        let postflopRoll = Double.random(in: 0...1)
        if postflopRoll < 0.25 {
            return .wonBeforeShowdown
        } else if postflopRoll < 0.45 {
            return .lostBeforeShowdown
        } else if postflopRoll < 0.72 {
            return .wonAtShowdown
        } else {
            return .lostAtShowdown
        }
    }

    // MARK: - Helpers

    private static func weightedRandom(_ weights: [Int: Int]) -> Int {
        let total = weights.values.reduce(0, +)
        var roll = Int.random(in: 0..<total)
        for (value, weight) in weights.sorted(by: { $0.key < $1.key }) {
            roll -= weight
            if roll < 0 { return value }
        }
        return weights.keys.first!
    }

    private static func weightedDuration() -> Double {
        let roll = Double.random(in: 0...1)
        if roll < 0.10 { return Double.random(in: 1.5...2.5) }  // Short session
        if roll < 0.35 { return Double.random(in: 2.5...3.5) }  // Medium-short
        if roll < 0.70 { return Double.random(in: 3.5...5.0) }  // Standard
        if roll < 0.90 { return Double.random(in: 5.0...6.5) }  // Long
        return Double.random(in: 6.5...8.0)                      // Marathon
    }

    private static func weightedStakes() -> String {
        let roll = Double.random(in: 0...1)
        if roll < 0.45 { return "1/2" }
        if roll < 0.75 { return "1/3" }
        if roll < 0.92 { return "2/5" }
        return "5/10"
    }

    private static func buyInForStakes(_ stakes: String) -> Double {
        switch stakes {
        case "1/2": return [200, 300, 300, 400].randomElement()!
        case "1/3": return [300, 300, 500, 500].randomElement()!
        case "2/5": return [500, 500, 1000, 1000].randomElement()!
        case "5/10": return [1000, 1500, 2000].randomElement()!
        default: return 300
        }
    }

    private static func generateCashOut(invested: Double, stakes: String, hours: Double) -> Double {
        // Slight winning player: +5bb/hr average with high variance
        let bbSize: Double
        switch stakes {
        case "1/2": bbSize = 2
        case "1/3": bbSize = 3
        case "2/5": bbSize = 5
        case "5/10": bbSize = 10
        default: bbSize = 2
        }

        // Expected win: +5bb/hr, but with huge standard deviation (~25bb/hr)
        let expectedWin = 5.0 * bbSize * hours
        let stdDev = 25.0 * bbSize * sqrt(hours)
        let randomResult = gaussianRandom() * stdDev + expectedWin

        let cashOut = max(0, invested + randomResult)
        return Double(Int(cashOut / 5) * 5) // Round to nearest $5
    }

    private static func weightedLocation(_ locations: [(String, Int)]) -> String {
        let total = locations.reduce(0) { $0 + $1.1 }
        var roll = Int.random(in: 0..<total)
        for (name, weight) in locations {
            roll -= weight
            if roll < 0 { return name }
        }
        return locations[0].0
    }

    private static func weightedMental(low: Int, mid: Int, high: Int) -> Int {
        let roll = Int.random(in: 0..<(low + mid + high))
        if roll < low { return Int.random(in: 1...2) }
        if roll < low + mid { return 3 }
        return Int.random(in: 4...5)
    }

    private static func gaussianRandom() -> Double {
        // Box-Muller transform
        let u1 = Double.random(in: 0.001...1.0)
        let u2 = Double.random(in: 0.0...1.0)
        return sqrt(-2.0 * log(u1)) * cos(2.0 * .pi * u2)
    }
}
