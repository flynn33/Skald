import Foundation

// ConversionError.swift (Custom errors for better debugging)
nonisolated enum ConversionError: Error {
    case invalidDocument
    case unsupportedFormat
    case jsonSerializationFailed
}

extension ConversionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidDocument:
            return "Invalid or unreadable document."
        case .unsupportedFormat:
            return "Unsupported document format."
        case .jsonSerializationFailed:
            return "Failed to serialize JSON output."
        }
    }
}
