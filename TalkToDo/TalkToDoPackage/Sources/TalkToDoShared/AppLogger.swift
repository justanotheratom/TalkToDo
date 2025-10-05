import Foundation
import os.log

/// Centralized logging utility for TalkToDo
public struct AppLogger {
    private static let subsystem = "com.talktodo.app"

    // MARK: - Logger Categories

    public static func ui() -> Logger {
        Logger(subsystem: subsystem, category: "UI")
    }

    public static func data() -> Logger {
        Logger(subsystem: subsystem, category: "Data")
    }

    public static func llm() -> Logger {
        Logger(subsystem: subsystem, category: "LLM")
    }

    public static func speech() -> Logger {
        Logger(subsystem: subsystem, category: "Speech")
    }

    public static func sync() -> Logger {
        Logger(subsystem: subsystem, category: "Sync")
    }
}

// MARK: - Logger Extensions

extension Logger {
    /// Log an event with optional structured data
    public func log(event: String, data: [String: Any] = [:]) {
        if data.isEmpty {
            self.info("\(event)")
        } else {
            let dataStr = data.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            self.info("\(event) | \(dataStr)")
        }
    }

    /// Log an error with structured context
    public func logError(event: String, error: Error, data: [String: Any] = [:]) {
        var context = data
        context["error"] = error.localizedDescription
        let dataStr = context.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        self.error("\(event) | \(dataStr)")
    }
}
