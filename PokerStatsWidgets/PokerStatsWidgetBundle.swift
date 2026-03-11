import SwiftUI
import WidgetKit

@main
struct PokerStatsWidgetBundle: WidgetBundle {
    var body: some Widget {
        PokerStatsLiveActivity()
        PokerStatsLifetimeWidget()
    }
}
