import ActivityKit
import Foundation

struct SessionActivityAttributes: ActivityAttributes {
    /// Fixed context that doesn't change during the activity
    let stakes: String
    let location: String
    let startTime: Date

    /// Dynamic state that updates during the activity
    struct ContentState: Codable, Hashable {
        let handCount: Int
        let totalInvested: Double
    }
}
