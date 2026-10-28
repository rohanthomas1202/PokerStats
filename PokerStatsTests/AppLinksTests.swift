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

    /// Send Feedback must open the same support page as the App Store
    /// Connect support URL, not the github.com placeholder (#282).
    @Test func feedback_isTheSupportURL() {
        #expect(AppLinks.feedback.absoluteString == "https://github.com/rohanthomas1202/PokerStats/issues")
    }

    /// The needs-support alert reads the one shared constant, so filling in
    /// AppLinks.supportEmail (#76) fixes every place that shows it.
    @MainActor
    @Test func needsSupportAlert_usesSharedSupportEmail() {
        #expect(AuthViewModel.DeleteAccountFailure.needsSupport.message.contains(AppLinks.supportEmail))
    }

    /// Records that the placeholder is still in place. When #76 is decided and
    /// supportEmail is filled in, this fails as a reminder to remove the
    /// placeholder gate in AppLinks.swift.
    @Test func supportEmail_isStillThePlaceholderUntil76() {
        #expect(AppLinks.supportEmail == AppLinks.supportEmailPlaceholder)
    }
}
