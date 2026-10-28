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
    @discardableResult
    func resolve(signedIn userId: UUID, storeIsEmpty: Bool) -> Status {
        if ownerId == nil || ownerId == userId || storeIsEmpty {
            adopt(userId)
            return .owned
        }
        return localOnlyUserId == userId ? .localOnly : .needsChoice
    }

    /// `userId` now owns the local data.
    func adopt(_ userId: UUID) {
        defaults.set(userId.uuidString, forKey: Self.ownerKey)
        defaults.removeObject(forKey: Self.localOnlyKey)
    }

    /// Keeps the current owner and blocks uploads while `userId` is signed in.
    func keepLocalOnly(for userId: UUID) {
        defaults.set(userId.uuidString, forKey: Self.localOnlyKey)
    }

    /// No local data left, so no owner.
    func clear() {
        defaults.removeObject(forKey: Self.ownerKey)
        defaults.removeObject(forKey: Self.localOnlyKey)
    }

    private func uuid(forKey key: String) -> UUID? {
        defaults.string(forKey: key).flatMap(UUID.init(uuidString:))
    }
}
