import Foundation

/// External pages the app links to.
enum AppLinks {
    /// Hosted privacy policy (PR #72). Must match fastlane/metadata/en-US/privacy_url.txt.
    static let privacyPolicy = URL(string: "https://rohanthomas1202.github.io/PokerStats/privacy/")!

    /// Support address shown in the delete-account needs-support alert.
    /// Placeholder until the owner picks the address in #76. When it is filled
    /// in, delete the placeholder checks below and in AppLinksTests.
    static let supportEmail = "[CONTACT_EMAIL]"
    static let supportEmailPlaceholder = "[CONTACT_EMAIL]"
}

// The placeholder must not reach App Review (#214). Debug builds (CI, local
// runs) stay green. Release archives (TestFlight and App Store) show a warning.
// A build with APP_STORE_SUBMISSION in SWIFT_ACTIVE_COMPILATION_CONDITIONS fails.
#if !DEBUG
#warning("AppLinks.supportEmail is still the [CONTACT_EMAIL] placeholder (#76).")
#endif
#if APP_STORE_SUBMISSION
#error("AppLinks.supportEmail is still the [CONTACT_EMAIL] placeholder (#76). Fill it in before App Store submission.")
#endif
