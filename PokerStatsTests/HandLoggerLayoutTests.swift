import SwiftUI
import Testing
@testable import PokerStats

@Suite("Hand Logger Layout")
struct HandLoggerLayoutTests {
    @Test(
        "Accessibility sizes stack actions and use two position columns",
        arguments: [
            DynamicTypeSize.accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5
        ]
    )
    func accessibilitySizes(size: DynamicTypeSize) {
        #expect(HandLoggerLayout.actionAxis(for: size) == .vertical)
        #expect(HandLoggerLayout.positionColumnCount(for: size) == 2)
        #expect(HandLoggerLayout.positionColumns(for: size).count == 2)
    }

    @Test(
        "Standard sizes keep actions horizontal with three position columns",
        arguments: [DynamicTypeSize.xSmall, .large, .xLarge, .xxLarge, .xxxLarge]
    )
    func standardSizes(size: DynamicTypeSize) {
        #expect(HandLoggerLayout.actionAxis(for: size) == .horizontal)
        #expect(HandLoggerLayout.positionColumnCount(for: size) == 3)
        #expect(HandLoggerLayout.positionColumns(for: size).count == 3)
    }
}
