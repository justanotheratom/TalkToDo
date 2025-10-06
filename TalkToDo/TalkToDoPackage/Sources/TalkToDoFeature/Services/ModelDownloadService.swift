import Foundation
import LeapSDK
@preconcurrency import LeapModelDownloader
import TalkToDoShared

public struct ModelDownloadResult: Sendable {
    public let localURL: URL
}

public enum ModelDownloadError: Error, Sendable {
    case cancelled
    case invalidURL
    case underlying(String)
}

public struct ModelDownloadService: Sendable {
    public init() {}

    public func downloadModel(
        entry: ModelCatalogEntry,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> ModelDownloadResult {
        // Extract filename from HuggingFace URL
        guard let filename = extractFilename(from: entry.huggingFaceURL) else {
            AppLogger.data().logError(
                event: "modelDownload:invalidURL",
                error: NSError(domain: "ModelDownload", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Invalid URL: \(entry.huggingFaceURL)"
                ])
            )
            throw ModelDownloadError.invalidURL
        }

        let hfModel = HuggingFaceDownloadableModel(
            ownerName: "LiquidAI",
            repoName: "LeapBundles",
            filename: filename
        )

        do {
            let downloadedURL = try await downloadWithLeapDownloader(model: hfModel, progress: progress)
            let storage = ModelStorageService()
            let expectedURL = try storage.expectedBundleURL(for: entry)

            AppLogger.data().log(event: "modelDownload:downloaded", data: [
                "modelSlug": entry.slug,
                "downloadedPath": downloadedURL.path,
                "expectedPath": expectedURL.path
            ])

            // Move to final location
            let fm = FileManager.default
            if fm.fileExists(atPath: expectedURL.path) {
                AppLogger.data().log(event: "modelDownload:removingExisting", data: [
                    "path": expectedURL.path
                ])
                try fm.removeItem(at: expectedURL)
            }

            let parentDir = expectedURL.deletingLastPathComponent()
            AppLogger.data().log(event: "modelDownload:creatingParentDir", data: [
                "path": parentDir.path
            ])
            try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)

            AppLogger.data().log(event: "modelDownload:movingFile", data: [
                "from": downloadedURL.path,
                "to": expectedURL.path
            ])

            // Check if source exists before moving
            var isSourceDir: ObjCBool = false
            let sourceExists = fm.fileExists(atPath: downloadedURL.path, isDirectory: &isSourceDir)

            // Check source file size
            var sourceSize: Int64 = 0
            if sourceExists, !isSourceDir.boolValue {
                if let attrs = try? fm.attributesOfItem(atPath: downloadedURL.path) {
                    sourceSize = attrs[.size] as? Int64 ?? 0
                }
            }

            AppLogger.data().log(event: "modelDownload:sourceCheck", data: [
                "exists": sourceExists,
                "isDirectory": isSourceDir.boolValue,
                "fileSize": sourceSize,
                "path": downloadedURL.path
            ])

            guard sourceExists else {
                throw ModelDownloadError.underlying("Source file/directory not found before move")
            }

            // If source is a tiny file, it's likely a symlink - try to resolve it
            if sourceSize < 1024 && sourceSize > 0 {
                AppLogger.data().log(event: "modelDownload:sourceIsSymlink", data: [
                    "fileSize": sourceSize,
                    "path": downloadedURL.path
                ])

                // Try to resolve the symlink
                if let resolvedPath = try? fm.destinationOfSymbolicLink(atPath: downloadedURL.path) {
                    AppLogger.data().log(event: "modelDownload:symlinkResolved", data: [
                        "originalPath": downloadedURL.path,
                        "resolvedPath": resolvedPath
                    ])

                    // Use the resolved path for copying
                    let resolvedURL = URL(fileURLWithPath: resolvedPath)
                    try fm.copyItem(at: resolvedURL, to: expectedURL)
                    try? fm.removeItem(at: downloadedURL)
                } else {
                    throw ModelDownloadError.underlying("Source appears to be symlink but cannot resolve: \(downloadedURL.path)")
                }
            } else {
                // Normal copy
                try fm.copyItem(at: downloadedURL, to: expectedURL)
                try? fm.removeItem(at: downloadedURL)
            }

            // Verify the bundle was moved successfully (bundles are directories)
            var isDestDir: ObjCBool = false
            let destExists = fm.fileExists(atPath: expectedURL.path, isDirectory: &isDestDir)

            AppLogger.data().log(event: "modelDownload:destCheck", data: [
                "exists": destExists,
                "isDirectory": isDestDir.boolValue,
                "path": expectedURL.path
            ])

            guard destExists else {
                throw ModelDownloadError.underlying("File move succeeded but bundle not found at destination")
            }

            AppLogger.data().log(event: "modelDownload:success", data: [
                "modelSlug": entry.slug,
                "path": expectedURL.path
            ])

            return ModelDownloadResult(localURL: expectedURL)
        } catch {
            AppLogger.data().logError(event: "modelDownload:failed", error: error, data: [
                "modelSlug": entry.slug
            ])
            throw ModelDownloadError.underlying("LeapModelDownloader failed: \(error.localizedDescription)")
        }
    }

    private func downloadWithLeapDownloader(
        model: HuggingFaceDownloadableModel,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> URL {
        let downloader = ModelDownloader()
        downloader.requestDownloadModel(model)

        var lastProgress: Double = 0
        while true {
            let status = await downloader.queryStatus(model)

            switch status {
            case .notOnLocal:
                try await Task.sleep(nanoseconds: 500_000_000)

            case .downloadInProgress(let currentProgress):
                if currentProgress != lastProgress {
                    lastProgress = currentProgress
                    progress(currentProgress)
                }
                try await Task.sleep(nanoseconds: 200_000_000)

            case .downloaded:
                progress(1.0)
                let url = downloader.getModelFile(model)
                return url

            @unknown default:
                try await Task.sleep(nanoseconds: 500_000_000)
            }

            if Task.isCancelled {
                throw ModelDownloadError.cancelled
            }
        }
    }

    private func extractFilename(from url: URL) -> String? {
        // Get the last path component and remove query parameters
        let lastComponent = url.lastPathComponent

        // Remove query parameters if present (e.g., "?download=true")
        let filename = lastComponent.components(separatedBy: "?").first ?? lastComponent

        // Verify it's a .bundle file
        guard filename.hasSuffix(".bundle") else {
            return nil
        }

        return filename
    }
}
