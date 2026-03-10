import Foundation
import Testing
@testable import PokerStats

@Suite("Session Computed Properties Tests")
struct SessionTests {

    @Test func totalInvested_includesRebuysAndAddOns() {
        let session = Session(buyIn: 200, rebuys: 100, addOns: 50)
        #expect(abs(session.totalInvested - 350.0) < 0.01)
    }

    @Test func netProfit_win() {
        let session = Session(buyIn: 200, cashOut: 500)
        #expect(abs(session.netProfit - 300.0) < 0.01)
    }

    @Test func netProfit_loss() {
        let session = Session(buyIn: 200, cashOut: 50)
        #expect(abs(session.netProfit - (-150.0)) < 0.01)
    }

    @Test func netProfit_withRebuys() {
        let session = Session(buyIn: 200, rebuys: 200, cashOut: 300)
        // Total invested: 400, cash out: 300, net: -100
        #expect(abs(session.netProfit - (-100.0)) < 0.01)
    }

    @Test func hourlyRate_validDuration() {
        let session = Session(
            startTime: Date(timeIntervalSinceNow: -7200), // 2 hours ago
            endTime: .now,
            buyIn: 200,
            cashOut: 400
        )
        let hourly = session.hourlyRate!
        // $200 profit / 2 hours = $100/hr
        #expect(abs(hourly - 100.0) < 1.0) // Allow small variance from time computation
    }

    @Test func hourlyRate_zeroDuration_returnsNil() {
        let now = Date()
        let session = Session(startTime: now, endTime: now, buyIn: 200, cashOut: 400)
        #expect(session.hourlyRate == nil)
    }

    @Test func roi_standardSession() {
        let session = Session(buyIn: 200, cashOut: 300)
        // ROI = 100/200 = 0.5 (50%)
        #expect(abs(session.roi! - 0.5) < 0.01)
    }

    @Test func roi_zeroBuyIn_returnsNil() {
        let session = Session(buyIn: 0, cashOut: 100)
        #expect(session.roi == nil)
    }

    @Test func isActive() {
        let active = Session()
        #expect(active.isActive == true)

        let completed = Session(status: .completed)
        #expect(completed.isActive == false)
    }

    @Test func nextHandNumber_noHands_returns1() {
        let session = Session()
        #expect(session.nextHandNumber == 1)
    }
}
