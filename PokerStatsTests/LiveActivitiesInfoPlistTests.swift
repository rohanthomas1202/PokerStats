import Foundation
import Testing

/// Checks the built app's Info.plist (#64). Unit tests run inside the app as
/// test host, so `Bundle.main` is the built PokerStats.app. Without
/// NSSupportsLiveActivities, Activity.request throws and no Live Activity shows.
@Suite("Live Activities Info.plist Tests")
struct LiveActivitiesInfoPlistTests {

    @Test func bundleMain_isTheApp() {
        #expect(Bundle.main.bundleIdentifier == "com.rohanthomas.PokerStats")
    }

    @Test func appInfoPlist_supportsLiveActivities() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "NSSupportsLiveActivities") as? Bool == true)
    }
}
