import Foundation

/// The 1.1 sync switch (#236). Off in every build configuration and every
/// fastlane lane: it is a plain constant, not a compilation condition or a
/// build setting, so no xcarg or scheme can turn it on.
///
/// While it is false, no app code path calls the sync types in this folder;
/// only tests use them. Turning it on is #85 and needs the owner's go-ahead
/// (docs/design/1.1-sync.md section 11 item 2).
enum SyncFeature {
    static let isEnabled = false
}
