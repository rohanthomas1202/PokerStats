import Foundation

/// Per-device record that the first auto-restore already ran, or that the
/// user deliberately deleted local data. Once set, auto-restore does not run
/// again on this device, so a wipe is never undone silently. Manual restore
/// in Settings > Cloud Backup ignores it. A reinstall clears it.
struct AutoRestoreFlag {
    static let key = "autoRestore.firstRestoreDone"

    let defaults: UserDefaults

    static var standard: AutoRestoreFlag { AutoRestoreFlag(defaults: .standard) }

    var isSet: Bool { defaults.bool(forKey: Self.key) }

    func set() { defaults.set(true, forKey: Self.key) }

    static let clearCountKey = "autoRestore.clearCount"

    /// Bumped by each `clear()` (account deletion), so a run that started
    /// before it can tell its restore is no longer wanted (#68).
    var clearCount: Int { defaults.integer(forKey: Self.clearCountKey) }

    func clear() {
        defaults.removeObject(forKey: Self.key)
        defaults.set(clearCount + 1, forKey: Self.clearCountKey)
    }
}
