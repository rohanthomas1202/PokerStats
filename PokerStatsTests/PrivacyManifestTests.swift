import Foundation
import Testing

/// Checks the privacy manifest shipped in the app bundle (#74). Unit tests run
/// inside the app as test host, so `Bundle.main` is the built PokerStats.app.
@Suite("Privacy Manifest Tests")
struct PrivacyManifestTests {

    private func manifestURL() throws -> URL {
        try #require(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
    }

    private func manifest() throws -> [String: Any] {
        let data = try Data(contentsOf: try manifestURL())
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(plist as? [String: Any])
    }

    @Test func manifest_isAtTheRootOfTheApp() throws {
        let folder = try manifestURL().deletingLastPathComponent().standardizedFileURL
        #expect(folder.path == Bundle.main.bundleURL.standardizedFileURL.path)
    }

    @Test func manifest_declaresNoTracking() throws {
        let manifest = try manifest()
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true)
    }

    /// The app's only required-reason API is UserDefaults.standard (AutoRestoreFlag).
    @Test func manifest_declaresUserDefaultsForAppOnlyData() throws {
        let types = try #require(try manifest()["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        #expect(types.count == 1)
        #expect(types.first?["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults")
        #expect(types.first?["NSPrivacyAccessedAPITypeReasons"] as? [String] == ["CA92.1"])
    }

    /// Matches docs/privacy/index.md: email and user ID from Sign in with Apple,
    /// and backups as user content. All linked, none used for tracking.
    @Test func manifest_collectedDataMatchesThePrivacyPolicy() throws {
        let collected = try #require(try manifest()["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        let names = collected.compactMap { $0["NSPrivacyCollectedDataType"] as? String }
        #expect(Set(names) == [
            "NSPrivacyCollectedDataTypeEmailAddress",
            "NSPrivacyCollectedDataTypeUserID",
            "NSPrivacyCollectedDataTypeOtherUserContent",
        ])
        #expect(names.count == 3)
        for entry in collected {
            #expect(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool == true)
            #expect(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool == false)
            #expect(entry["NSPrivacyCollectedDataTypePurposes"] as? [String]
                == ["NSPrivacyCollectedDataTypePurposeAppFunctionality"])
        }
    }
}
