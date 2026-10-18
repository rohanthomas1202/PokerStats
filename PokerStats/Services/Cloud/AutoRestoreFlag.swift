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

    func clear() { defaults.removeObject(forKey: Self.key) }
}
