import SwiftUI

@main
struct PhotoPlayerApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                LibraryScreen().tabItem { Label("動画", systemImage: "play.rectangle") }
                CounterView().tabItem { Label("導入確認", systemImage: "checkmark.circle") }
            }
        }
    }
}
