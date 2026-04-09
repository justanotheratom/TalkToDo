import SwiftUI
import SwiftData
import TalkToDoFeature
import TalkToDoShared

@main
struct TalkToDoApp: App {
    let modelContainer: ModelContainer
    @StateObject private var fontPreference = FontPreference()

    init() {
        modelContainer = AppModelContainerFactory.makeModelContainer(
            cloudKitIdentifier: "iCloud.com.talktodo.macos",
            useCloudKit: Self.shouldUseCloudKit
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(fontPreference)
        }
        .modelContainer(modelContainer)
    }

    private static var shouldUseCloudKit: Bool {
        if ProcessInfo.processInfo.environment["TALKTODO_DISABLE_CLOUDKIT"] == "1" {
            return false
        }

        return true
    }
}
