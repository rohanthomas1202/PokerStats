import Foundation
import SwiftUI
import Testing
import UIKit
@testable import PokerStats

@Suite("Hand Logger Contrast")
@MainActor
struct HandLoggerContrastTests {
    @Test("Logger text and glyph palettes exceed 4.5:1 in both appearances", arguments: [false, true])
    func buttonContrast(dark: Bool) {
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        let pairs: [(foreground: Color, background: Color)] = [
            (.black, .pokerAccent),
            (.black, .pokerProfit),
            (.black, .pokerLoss),
            (.black, .orange),
            (.white, .pokerCard)
        ]
        for pair in pairs {
            let foreground = luminance(UIColor(pair.foreground).resolvedColor(with: traits))
            let background = luminance(UIColor(pair.background).resolvedColor(with: traits))
            let ratio = (max(foreground, background) + 0.05) / (min(foreground, background) + 0.05)
            #expect(ratio >= 4.5)
        }
    }

    private func luminance(_ color: UIColor) -> Double {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        #expect(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        #expect(alpha == 1)
        func linear(_ component: CGFloat) -> Double {
            let value = Double(component)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}
