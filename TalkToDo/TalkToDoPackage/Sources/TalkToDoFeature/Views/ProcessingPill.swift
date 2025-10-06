import SwiftUI

/// Shows processing state with user's transcript and animated indicator
@available(iOS 18.0, macOS 15.0, *)
struct ProcessingPill: View {
    let transcript: String
    let isError: Bool

    var body: some View {
        HStack(spacing: 12) {
            if !isError {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color(red: 1.0, green: 0.478, blue: 0.361))
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(isError ? "Processing failed" : "Creating tasks…")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isError ? .orange : .primary)

                Text(transcript)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(
                    isError ? Color.orange.opacity(0.3) : Color(red: 1.0, green: 0.478, blue: 0.361).opacity(0.2),
                    lineWidth: 1
                )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

#Preview {
    VStack {
        ProcessingPill(transcript: "Buy milk eggs and bread from the store", isError: false)
        ProcessingPill(transcript: "Failed to process this request", isError: true)
    }
}
