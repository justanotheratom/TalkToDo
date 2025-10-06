import SwiftUI

@available(iOS 18.0, macOS 15.0, *)
public struct AttributionsView: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                Section("Language Models") {
                    AttributionRow(
                        name: "LFM2-700M / LFM2-1.2B",
                        author: "Liquid AI",
                        license: "Apache 2.0",
                        url: "https://www.liquid.ai/liquid-foundation-models"
                    )
                }

                Section("Open Source Libraries") {
                    AttributionRow(
                        name: "Leap iOS SDK",
                        author: "Liquid AI",
                        license: "Apache 2.0",
                        url: "https://github.com/Liquid4All/leap-ios"
                    )

                    AttributionRow(
                        name: "Swift Syntax",
                        author: "Apple Inc.",
                        license: "Apache 2.0",
                        url: "https://github.com/swiftlang/swift-syntax"
                    )
                }

                Section("Apple Frameworks") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SwiftUI, SwiftData, CloudKit, Speech")
                            .font(.body)
                        Text("© Apple Inc.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Attributions")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
                #else
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                #endif
            }
        }
    }
}

@available(iOS 18.0, macOS 15.0, *)
private struct AttributionRow: View {
    let name: String
    let author: String
    let license: String
    let url: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.body)
                .fontWeight(.medium)

            Text(author)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(license)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.15))
                    )

                if let url = URL(string: url) {
                    Link(destination: url) {
                        HStack(spacing: 2) {
                            Text("Learn more")
                            Image(systemName: "arrow.up.right.square")
                        }
                        .font(.caption2)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    AttributionsView()
}
