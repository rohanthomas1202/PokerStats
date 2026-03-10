import Foundation
import Testing
@testable import PokerStats

@Suite("TiltTracker Tests")
struct TiltTrackerTests {

    // MARK: - Mental Correlation

    @Test func mentalCorrelation_noSessions_returnsEmpty() {
        let result = TrendCalculator.mentalCorrelation(sessions: [])
        #expect(result.isEmpty)
    }

    @Test func mentalCorrelation_sessionsWithNilMental_excluded() {
        // Session without mental data
        let session = TestHelpers.completedSession(buyIn: 200, cashOut: 300)
        let result = TrendCalculator.mentalCorrelation(sessions: [session])
        #expect(result.isEmpty)
    }

    @Test func mentalCorrelation_sessionsWithMentalData_computesCorrectly() {
        // Calm session (tilt=1): $50/hr profit
        let s1 = TestHelpers.completedSession(buyIn: 200, cashOut: 300, hours: 2) // +$100 = $50/hr
        s1.tiltLevel = 1
        s1.energyLevel = 4
        s1.focusLevel = 5

        // Tilted session (tilt=5): -$50/hr
        let s2 = TestHelpers.completedSession(buyIn: 200, cashOut: 100, hours: 2) // -$100 = -$50/hr
        s2.tiltLevel = 5
        s2.energyLevel = 2
        s2.focusLevel = 1

        let result = TrendCalculator.mentalCorrelation(sessions: [s1, s2])

        // Should have points for tilt, energy, and focus
        let tiltPoints = result.filter { $0.metricType == .tilt }
        let energyPoints = result.filter { $0.metricType == .energy }
        let focusPoints = result.filter { $0.metricType == .focus }

        #expect(tiltPoints.count == 2) // level 1 and level 5
        #expect(energyPoints.count == 2) // level 4 and level 2
        #expect(focusPoints.count == 2) // level 5 and level 1

        // Verify tilt correlation: calm should be positive
        if let calm = tiltPoints.first(where: { $0.level == 1 }) {
            #expect(calm.averageHourlyRate > 0)
            #expect(calm.sessionCount == 1)
        }

        // Tilted should be negative
        if let tilted = tiltPoints.first(where: { $0.level == 5 }) {
            #expect(tilted.averageHourlyRate < 0)
            #expect(tilted.sessionCount == 1)
        }
    }

    @Test func mentalCorrelation_multipleSessions_sameTiltLevel_averages() {
        // Two calm sessions with different hourly rates
        let s1 = TestHelpers.completedSession(buyIn: 200, cashOut: 400, hours: 2) // +$200 = $100/hr
        s1.tiltLevel = 1

        let s2 = TestHelpers.completedSession(buyIn: 200, cashOut: 300, hours: 2) // +$100 = $50/hr
        s2.tiltLevel = 1

        let result = TrendCalculator.mentalCorrelation(sessions: [s1, s2])
        let tiltPoints = result.filter { $0.metricType == .tilt }

        if let calm = tiltPoints.first(where: { $0.level == 1 }) {
            // Average of $100/hr and $50/hr = $75/hr
            #expect(abs(calm.averageHourlyRate - 75.0) < 0.01)
            #expect(calm.sessionCount == 2)
        }
    }

    @Test func mentalCorrelation_singleLevel_edgeCase() {
        // All sessions at the same tilt level
        let s1 = TestHelpers.completedSession(buyIn: 200, cashOut: 300, hours: 2)
        s1.tiltLevel = 3
        s1.energyLevel = 3
        s1.focusLevel = 3

        let result = TrendCalculator.mentalCorrelation(sessions: [s1])
        let tiltPoints = result.filter { $0.metricType == .tilt }
        #expect(tiltPoints.count == 1)
        #expect(tiltPoints[0].level == 3)
    }
}
