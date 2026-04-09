import SwiftData
import TalkToDoShared

public enum AppModelContainerFactory {
    public static func makeModelContainer(
        cloudKitIdentifier: String,
        useCloudKit: Bool
    ) -> ModelContainer {
        let schema = Schema([NodeEvent.self])
        let logger = AppLogger.sync()

        if useCloudKit {
            do {
                let configuration = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: false,
                    cloudKitDatabase: .private(cloudKitIdentifier)
                )
                return try ModelContainer(
                    for: schema,
                    configurations: [configuration]
                )
            } catch {
                logger.error(
                    "CloudKit model container setup failed. Falling back to local store. error=\(error.localizedDescription, privacy: .public)"
                )
            }
        } else {
            logger.warning("CloudKit disabled for this launch. Using local SwiftData store.")
        }

        do {
            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )
            return try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
        } catch {
            fatalError("Failed to configure local ModelContainer: \(error)")
        }
    }
}
