import SwiftUI

@main
struct LogicManagerApp: App {
    @StateObject private var store = ScoreStore()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1100, minHeight: 650)
        }
    }
}
