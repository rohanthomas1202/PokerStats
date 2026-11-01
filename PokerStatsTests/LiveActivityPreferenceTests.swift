import Foundation
import Testing
@testable import PokerStats

/// #286: Settings > Live Activity > Show on Lock Screen decides whether a
/// session starts a Live Activity. Default on.
@Suite("Live Activity Preference Tests")
@MainActor
struct LiveActivityPreferenceTests {
    private let defaults = ThrowawayDefaults("LiveActivityPreferenceTests")

    @Test func unset_defaultsToOn() {
        let preference = LiveActivityPreference(defaults: defaults)
        #expect(preference.showOnLockScreen)
        #expect(LiveActivityPreference.defaultValue)
    }

    @Test func toggleOff_isRead() {
        // @AppStorage in SettingsView writes a Bool under this key.
        defaults.set(false, forKey: LiveActivityPreference.key)
        #expect(!LiveActivityPreference(defaults: defaults).showOnLockScreen)
    }

    @Test func toggleBackOn_isRead() {
        defaults.set(false, forKey: LiveActivityPreference.key)
        defaults.set(true, forKey: LiveActivityPreference.key)
        #expect(LiveActivityPreference(defaults: defaults).showOnLockScreen)
    }

    @Test func toggleOff_startsNoActivity() {
        #expect(!LiveActivityPreference.shouldStart(showOnLockScreen: false, activitiesEnabled: true))
        #expect(!LiveActivityPreference.shouldStart(showOnLockScreen: false, activitiesEnabled: false))
    }

    @Test func toggleOn_startsOnlyWhenIOSAllows() {
        #expect(LiveActivityPreference.shouldStart(showOnLockScreen: true, activitiesEnabled: true))
        #expect(!LiveActivityPreference.shouldStart(showOnLockScreen: true, activitiesEnabled: false))
    }
}
