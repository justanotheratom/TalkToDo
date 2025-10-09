import SwiftUI

@available(iOS 18.0, macOS 15.0, *)
public struct AboutView: View {
    public init() {}

    public var body: some View {
        Form {
            Section {
                VStack(spacing: 16) {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue)

                    Text("TalkToDo")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Version 1.0.0")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A voice-first hierarchical todo app powered by AI.")
                        .font(.callout)

                    Text("Speak naturally and watch your thoughts transform into structured lists.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("About")
            }

            Section {
                Link(destination: URL(string: "https://x.com/realsanketp")!) {
                    Label("X", systemImage: "link")
                }

                Link(destination: URL(string: "https://github.com/justanotheratom")!) {
                    Label("GitHub", systemImage: "link")
                }

                Link(destination: URL(string: "https://www.linkedin.com/in/realsanketp/")!) {
                    Label("LinkedIn", systemImage: "link")
                }
            } header: {
                Text("About Me")
            }

            Section {
                NavigationLink("Attributions") {
                    AttributionsView()
                }
            }
        }
        .navigationTitle("About")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
