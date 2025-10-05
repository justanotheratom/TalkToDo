import Foundation
import TalkToDoShared

public struct ModelStorageService: Sendable {
    public init() {}

    public func modelsRootDirectory() throws -> URL {
        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport.appendingPathComponent("Models", isDirectory: true)
    }

    public func expectedResourceURL(for entry: ModelCatalogEntry) throws -> URL {
        try expectedBundleURL(for: entry)
    }

    public func expectedBundleURL(for entry: ModelCatalogEntry) throws -> URL {
        let root = try modelsRootDirectory()
        let name = "\(entry.quantizationSlug).bundle"
        return root.appendingPathComponent(name, isDirectory: false)
    }

    public func isDownloaded(entry: ModelCatalogEntry) -> Bool {
        do {
            let url = try expectedResourceURL(for: entry)
            return isLeapBundleDownloaded(at: url)
        } catch {
            AppLogger.data().logError(event: "storage:checkFailed", error: error, data: [
                "modelSlug": entry.slug
            ])
            return false
        }
    }

    public func deleteDownloadedModel(entry: ModelCatalogEntry) throws {
        let url = try expectedResourceURL(for: entry)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
            AppLogger.data().log(event: "storage:modelDeleted", data: [
                "modelSlug": entry.slug,
                "path": url.path
            ])
        }
    }

    private func isLeapBundleDownloaded(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

        guard exists else {
            return false
        }

        if isDir.boolValue {
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path) {
                return !contents.isEmpty
            } else {
                AppLogger.data().log(event: "storage:contentsReadFailed", data: [
                    "path": url.path
                ])
                return false
            }
        } else {
            do {
                let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                let fileSize = attrs[.size] as? Int64 ?? 0
                return fileSize > 1024
            } catch {
                AppLogger.data().logError(event: "storage:attributeReadFailed", error: error, data: [
                    "path": url.path
                ])
                return false
            }
        }
    }
}
