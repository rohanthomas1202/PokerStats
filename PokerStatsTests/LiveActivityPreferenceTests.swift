import Foundation
import Testing
@testable import PokerStats

/// #286: Settings > Live Activity > Show Live Activity decides whether a
/// session starts a Live Activity. Default on.
///
/// Each test that reads the setting makes its own ThrowawayDefaults and holds
/// it for the whole test, like `freshFlag()` in AutoRestoreTests. The suite
/// keeps no stored UserDefaults, so the pure-function tests never touch
/// defaults, and it runs serialized so no two tests share a suite.
@Suite("Live Activity Preference Tests", .serialized)
@MainActor
struct LiveActivityPreferenceTests {

    @Test func settingsFooter_describesTheLockScreenFields() throws {
        let view = try TestHelpers.repositoryFile("PokerStats/Views/Settings/SettingsView.swift")
        let footer = "Shows your stakes, session timer and hand count on the Lock Screen and in the Dynamic Island. Amount invested and location appear only when iPhone is unlocked."
        #expect(view.contains("Text(\"\(footer)\")"))
    }

    @Test func unset_defaultsToOn() {
        let defaults = ThrowawayDefaults("LiveActivityPreferenceTests")
        #expect(LiveActivityPreference(defaults: defaults).showOnLockScreen)
        #expect(LiveActivityPreference.defaultValue)
    }

    @Test func toggleOff_isRead() {
        let defaults = ThrowawayDefaults("LiveActivityPreferenceTests")
        // @AppStorage in SettingsView writes a Bool under this key.
        defaults.set(false, forKey: LiveActivityPreference.key)
        #expect(!LiveActivityPreference(defaults: defaults).showOnLockScreen)
    }

    @Test func toggleBackOn_isRead() {
        let defaults = ThrowawayDefaults("LiveActivityPreferenceTests")
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

    @Test func toggleOff_endsRunningActivity() {
        var endCalls = 0
        LiveActivityPreference.handleToggleChange(to: false) { endCalls += 1 }
        #expect(endCalls == 1)
    }

    @Test func toggleOn_doesNotEndActivity() {
        var endCalls = 0
        LiveActivityPreference.handleToggleChange(to: true) { endCalls += 1 }
        #expect(endCalls == 0)
    }
}
