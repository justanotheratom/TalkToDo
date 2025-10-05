import Foundation

/// Catalog entry for an LFM2 model
public struct ModelCatalogEntry: Identifiable, Hashable, Sendable {
    public let id: String
    public let slug: String
    public let displayName: String
    public let quantizationSlug: String
    public let huggingFaceURL: URL
    public let estimatedSizeMB: Int
    public let recommendedPlatform: Platform

    public enum Platform: Sendable {
        case iOS
        case macOS
        case both
    }

    public init(
        slug: String,
        displayName: String,
        quantizationSlug: String,
        huggingFaceURL: URL,
        estimatedSizeMB: Int,
        recommendedPlatform: Platform
    ) {
        self.id = slug
        self.slug = slug
        self.displayName = displayName
        self.quantizationSlug = quantizationSlug
        self.huggingFaceURL = huggingFaceURL
        self.estimatedSizeMB = estimatedSizeMB
        self.recommendedPlatform = recommendedPlatform
    }
}

/// Catalog of available LFM2 models for TalkToDo
public struct ModelCatalog {
    public static let lfm2_700M = ModelCatalogEntry(
        slug: "lfm2-700m-q4",
        displayName: "LFM2 700M (Q4)",
        quantizationSlug: "q4",
        huggingFaceURL: URL(string: "https://huggingface.co/Liquid4All/LFM-2-700M-Q4")!,
        estimatedSizeMB: 450,
        recommendedPlatform: .iOS
    )

    public static let lfm2_1_2B = ModelCatalogEntry(
        slug: "lfm2-1.2b-q4",
        displayName: "LFM2 1.2B (Q4)",
        quantizationSlug: "q4",
        huggingFaceURL: URL(string: "https://huggingface.co/Liquid4All/LFM-2-1.2B-Q4")!,
        estimatedSizeMB: 750,
        recommendedPlatform: .macOS
    )

    public static let all: [ModelCatalogEntry] = [
        lfm2_700M,
        lfm2_1_2B
    ]

    #if os(iOS)
    public static let defaultModel = lfm2_700M
    #else
    public static let defaultModel = lfm2_1_2B
    #endif

    public static func model(forSlug slug: String) -> ModelCatalogEntry? {
        all.first { $0.slug == slug }
    }
}
