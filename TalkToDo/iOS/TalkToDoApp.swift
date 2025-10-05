import SwiftUI
import SwiftData

@main
struct TalkToDoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [/* SwiftData models will be added in Phase 2 */])
    }
}
