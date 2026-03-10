import Foundation
import Testing
@testable import PokerStats

@Suite("PlayStyle Classification Tests")
struct PlayStyleTests {

    @Test func classify_TAG_profile() {
        // VPIP 22%, PFR 18% — classic TAG
        let style = PlayStyle.classify(vpip: 0.22, pfr: 0.18)
        #expect(style == .tag)
    }

    @Test func classify_fish_profile() {
        // VPIP 45%, PFR 8% — loose passive = fish
        let style = PlayStyle.classify(vpip: 0.45, pfr: 0.08)
        #expect(style == .fish)
    }

    @Test func classify_nit_profile() {
        // VPIP 8%, PFR 6% — extremely tight = nit
        let style = PlayStyle.classify(vpip: 0.08, pfr: 0.06)
        #expect(style == .nit)
    }

    @Test func classify_maniac_profile() {
        // VPIP 50%, PFR 40% — very loose very aggressive = maniac
        let style = PlayStyle.classify(vpip: 0.50, pfr: 0.40)
        #expect(style == .maniac)
    }

    @Test func classify_nil_vpip_returnsNil() {
        let style = PlayStyle.classify(vpip: nil, pfr: 0.18)
        #expect(style == nil)
    }

    @Test func classify_nil_pfr_returnsNil() {
        let style = PlayStyle.classify(vpip: 0.22, pfr: nil)
        #expect(style == nil)
    }

    @Test func classify_bothNil_returnsNil() {
        let style = PlayStyle.classify(vpip: nil, pfr: nil)
        #expect(style == nil)
    }

    @Test func classify_rock_profile() {
        // VPIP 15%, PFR 12% — tight aggressive but very tight = rock
        let style = PlayStyle.classify(vpip: 0.15, pfr: 0.12)
        #expect(style == .rock)
    }

    @Test func classify_LAG_profile() {
        // VPIP 35%, PFR 28% — loose aggressive
        let style = PlayStyle.classify(vpip: 0.35, pfr: 0.28)
        #expect(style == .lag)
    }

    @Test func classify_passive_profile() {
        // VPIP 25%, PFR 5% — normal VPIP but barely raises = passive
        let style = PlayStyle.classify(vpip: 0.25, pfr: 0.05)
        #expect(style == .passive)
    }
}
