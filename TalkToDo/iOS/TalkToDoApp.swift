import SwiftUI
import SwiftData
import TalkToDoFeature

@main
struct TalkToDoApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            // Configure SwiftData with CloudKit sync
            let schema = Schema([NodeEvent.self])
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .private("iCloud.com.talktodo.ios")
            )
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Failed to configure ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
