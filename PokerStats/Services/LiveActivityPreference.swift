import Foundation

/// Whether starting a session also starts its Live Activity on the Lock
/// Screen and in the Dynamic Island (#286). Settings writes it through
/// @AppStorage with the same key and default. Stored per device in
/// UserDefaults, like `AutoRestoreFlag`. On unless the user turns it off.
struct LiveActivityPreference {
    /// The key name predates the "Show Live Activity" toggle label and is
    /// kept as is: it shipped in #286, and renaming it would reset anyone
    /// who turned the toggle off back to on unless the value were migrated.
    static let key = "liveActivity.showOnLockScreen"
    static let defaultValue = true

    let defaults: UserDefaults

    static var standard: LiveActivityPreference { LiveActivityPreference(defaults: .standard) }

    var showOnLockScreen: Bool {
        defaults.object(forKey: Self.key) as? Bool ?? Self.defaultValue
    }

    /// A new Live Activity starts only when both the Settings toggle and
    /// iOS allow it.
    static func shouldStart(showOnLockScreen: Bool, activitiesEnabled: Bool) -> Bool {
        showOnLockScreen && activitiesEnabled
    }

    /// Turning the toggle off ends any running Live Activity right away.
    /// Turning it back on does nothing until the next session starts.
    static func handleToggleChange(to showOnLockScreen: Bool, endLiveActivities: () -> Void) {
        if !showOnLockScreen {
            endLiveActivities()
        }
    }
}
