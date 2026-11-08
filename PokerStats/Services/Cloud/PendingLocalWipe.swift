import Foundation

/// Per-device record that the local wipe after account deletion failed, so
/// Settings asks again after Not Now or a relaunch (#273). Stored in
/// UserDefaults, like `AutoRestoreFlag`. Cleared once a wipe works.
struct PendingLocalWipe {
    static let key = "localWipe.pendingAfterAccountDeletion"

    let defaults: UserDefaults

    static var standard: PendingLocalWipe { PendingLocalWipe(defaults: .standard) }

    var isSet: Bool { defaults.bool(forKey: Self.key) }

    func set() { defaults.set(true, forKey: Self.key) }

    func clear() { defaults.removeObject(forKey: Self.key) }
}
