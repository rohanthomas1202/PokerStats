import Foundation
import Testing
@testable import PokerStats

@Suite("App Links Tests")
struct AppLinksTests {

    /// App Review 5.1.1(i): the in-app link must open the same hosted policy
    /// as the App Store Connect privacy URL.
    @Test func privacyPolicy_isTheHostedPolicy() {
        #expect(AppLinks.privacyPolicy.absoluteString == "https://rohanthomas1202.github.io/PokerStats/privacy/")
    }
}
