import SwiftUI

@available(iOS 18.0, macOS 15.0, *)
public struct StatusBadge: View {
    public enum Status {
        case installed
        case notConfigured
        case ready
        case downloading(progress: Double)

        var color: Color {
            switch self {
            case .installed: return .green
            case .notConfigured: return .orange
            case .ready: return .blue
            case .downloading: return .blue
            }
        }

        var label: String {
            switch self {
            case .installed: return "Installed"
            case .notConfigured: return "Setup Required"
            case .ready: return "Ready"
            case .downloading(let p): return "Downloading \(Int(p * 100))%"
            }
        }

        var icon: String {
            switch self {
            case .installed: return "checkmark.circle.fill"
            case .notConfigured: return "exclamationmark.circle.fill"
            case .ready: return "circle.fill"
            case .downloading: return "arrow.down.circle"
            }
        }
    }

    let status: Status

    public init(status: Status) {
        self.status = status
    }

    public var body: some View {
        Label(status.label, systemImage: status.icon)
            .font(.caption)
            .foregroundStyle(status.color)
    }
}
