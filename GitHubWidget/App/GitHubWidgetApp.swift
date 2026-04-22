import SwiftUI

@main
struct GitHubWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings scene keeps app alive with no windows; LSUIElement in Info.plist hides dock icon
        Settings { EmptyView() }
    }
}
