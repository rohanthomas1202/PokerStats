import Foundation

/// Per-device record that the local wipe after account deletion failed, so
/// Settings asks again after Not Now or a relaunch (#273). Stored in
/// UserDefaults, like `AutoRestoreFlag`. It names the deleted account's
/// local data owner and counts only while that owner still holds the data
/// and nobody is signed in, so it never offers to wipe another account's data.
/// Cleared once a wipe works, on sign-in, and by Delete All Data.
struct PendingLocalWipe {
    static let key = "localWipe.pendingOwnerId"
    /// Stored when the data had no owner.
    private static let noOwner = "none"

    let defaults: UserDefaults

    static var standard: PendingLocalWipe { PendingLocalWipe(defaults: .standard) }

    /// True when a failed wipe was recorded for any owner.
    var isRecorded: Bool { defaults.string(forKey: Self.key) != nil }

    func isPending(owner: LocalDataOwner, isSignedIn: Bool) -> Bool {
        guard !isSignedIn, let stored = defaults.string(forKey: Self.key) else { return false }
        return stored == (owner.ownerId?.uuidString ?? Self.noOwner)
    }

    func set(owner: LocalDataOwner) {
        defaults.set(owner.ownerId?.uuidString ?? Self.noOwner, forKey: Self.key)
    }

    func clear() { defaults.removeObject(forKey: Self.key) }
}
