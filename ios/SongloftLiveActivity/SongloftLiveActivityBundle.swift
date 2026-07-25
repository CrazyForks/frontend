import WidgetKit
import SwiftUI

@main
struct SongloftLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        SongloftLiveActivityWidget()
        SongloftNowPlayingWidget()
    }
}