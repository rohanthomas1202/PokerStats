import CryptoKit
import Foundation
import Security

/// One-time nonce for an ID-token sign-in. Apple gets the SHA-256 hash and
/// puts it in the ID token's `nonce` claim; Supabase gets the raw value and
/// checks it hashes to that claim, so a captured ID token can't be replayed.
/// Kept in memory for one attempt only; never persisted.
struct SignInNonce: Equatable, Sendable {
    static let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")

    let raw: String
    var hashed: String { Self.sha256Hex(raw) }

    init(length: Int = 32) {
        raw = Self.randomString(length: length)
    }

    static func sha256Hex(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Rejection sampling over `SecRandomCopyBytes` so every character is equally likely.
    private static func randomString(length: Int) -> String {
        precondition(length > 0)
        let limit = 256 - (256 % charset.count)
        var result = ""
        result.reserveCapacity(length)
        while result.count < length {
            var bytes = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
            for byte in bytes where Int(byte) < limit && result.count < length {
                result.append(charset[Int(byte) % charset.count])
            }
        }
        return result
    }
}
