import Foundation

/// Which account the stats on this device belong to, so one account's data
/// is never backed up to another account (#69). Stored per device in
/// UserDefaults, like `AutoRestoreFlag`. Sign Out keeps it.
///
/// No owner means the data was never tied to an account (the app works
/// without one); the next sign-in or backup adopts it.
struct LocalDataOwner {
    static let ownerKey = "localData.ownerUserId"
    static let localOnlyKey = "localData.localOnlyUserId"
    static let unsentChangesKey = "localData.hasUnsentChanges"
    /// Posted after the owner or the keep-local choice changes, with the
    /// `UserDefaults` it was stored in as the object, so
    /// `LocalDataOwnershipViewModel` re-reads it after every change (#264).
    static let didChangeNotification = Notification.Name("LocalDataOwner.didChange")

    /// What a sign-in found.
    enum Status: Equatable {
        /// The signed-in account owns the local data; backups run as before.
        case owned
        /// Another account's data is on this device; nothing uploads until the user chooses.
        case needsChoice
        /// The user chose to keep another account's data on this device only; nothing uploads.
        case localOnly
    }

    let defaults: UserDefaults

    static var standard: LocalDataOwner { LocalDataOwner(defaults: .standard) }

    var ownerId: UUID? { uuid(forKey: Self.ownerKey) }

    /// The signed-in account that chose to keep another account's data on this device only.
    var localOnlyUserId: UUID? { uuid(forKey: Self.localOnlyKey) }

    /// True when the local data may be uploaded to `userId`'s backups.
    func allowsUpload(for userId: UUID) -> Bool {
        ownerId == nil || ownerId == userId
    }

    /// Runs when `userId` signs in, or is found signed in at launch. The same
    /// account, a device whose data has no owner yet, and an empty store all
    /// keep today's behavior: the account owns the data.
    ///
    /// A device updated from a build without an owner key has no owner, so
    /// the first account to sign in after the update takes the data without
    /// being asked, even if another account used it before. This happens once
    /// per device and can't be detected, since the earlier build stored no
    /// owner (#264); the release notes say so.
    @discardableResult
    func resolve(signedIn userId: UUID, storeIsEmpty: Bool) -> Status {
        if ownerId == nil || ownerId == userId || storeIsEmpty {
            adopt(userId)
            return .owned
        }
        return localOnlyUserId == userId ? .localOnly : .needsChoice
    }

    /// Local changes no backup has sent yet (#293). Stored here so they are
    /// still sent at the next sign-in after the app is relaunched (#300).
    var hasUnsentChanges: Bool {
        get { defaults.bool(forKey: Self.unsentChangesKey) }
        nonmutating set {
            if newValue {
                defaults.set(true, forKey: Self.unsentChangesKey)
            } else {
                defaults.removeObject(forKey: Self.unsentChangesKey)
            }
        }
    }

    /// `userId` now owns the local data. When it took the data from another
    /// account, that account's unsent changes are no longer owed to anyone,
    /// so the flag is cleared (#311). Data with no owner keeps its flag.
    func adopt(_ userId: UUID) {
        if let ownerId, ownerId != userId {
            hasUnsentChanges = false
        }
        defaults.set(userId.uuidString, forKey: Self.ownerKey)
        defaults.removeObject(forKey: Self.localOnlyKey)
        postChange()
    }

    /// Keeps the current owner and blocks uploads while `userId` is signed in.
    func keepLocalOnly(for userId: UUID) {
        defaults.set(userId.uuidString, forKey: Self.localOnlyKey)
        postChange()
    }

    /// No local data left, so no owner and nothing unsent.
    func clear() {
        defaults.removeObject(forKey: Self.ownerKey)
        defaults.removeObject(forKey: Self.localOnlyKey)
        defaults.removeObject(forKey: Self.unsentChangesKey)
        postChange()
    }

    private func postChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: defaults)
    }

    private func uuid(forKey key: String) -> UUID? {
        defaults.string(forKey: key).flatMap(UUID.init(uuidString:))
    }
}
