import Foundation

/// Utility for generating and validating 16-bit hex node IDs
public struct NodeID {
    /// Generate a random 4-character hex ID (e.g., "a3f2")
    public static func generate() -> String {
        let value = UInt16.random(in: 0...UInt16.max)
        return String(format: "%04x", value)
    }

    /// Validate that a string is a valid 4-character hex ID
    public static func isValid(_ id: String) -> Bool {
        id.count == 4 && id.allSatisfy { $0.isHexDigit }
    }

    /// Generate a batch ID (UUID for grouping events)
    public static func generateBatchID() -> String {
        UUID().uuidString
    }
}
