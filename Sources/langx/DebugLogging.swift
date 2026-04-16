import Foundation

enum AppLogLevel: String, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case error = "ERROR"
}

struct AppLogEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    let timestamp: Date
    let level: AppLogLevel
    let category: String
    let message: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: AppLogLevel,
        category: String,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
    }
}

typealias AppLogHandler = @Sendable (AppLogLevel, String, String) async -> Void

enum AppLogger {
    static let noop: AppLogHandler = { _, _, _ in }
}

enum DebugLogFormatter {
    static func command(executablePath: String, arguments: [String]) -> String {
        ([String(reflecting: executablePath)] + arguments.map { String(reflecting: $0) })
            .joined(separator: " ")
    }

    static func preview(_ text: String, limit: Int = 180) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "\\n")

        guard normalized.count > limit else {
            return normalized
        }

        let endIndex = normalized.index(normalized.startIndex, offsetBy: limit)
        return "\(normalized[..<endIndex])..."
    }
}
