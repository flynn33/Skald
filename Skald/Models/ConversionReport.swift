import Foundation

nonisolated enum ConversionStatus: String, Sendable {
    case converted
    case empty
    case skipped
    case failed

    var label: String {
        rawValue.capitalized
    }
}

nonisolated struct ConversionEntry: Identifiable, Sendable {
    let id = UUID()
    let fileName: String
    let fileExtension: String
    let status: ConversionStatus
    let message: String?
    let outputURL: URL?
}

nonisolated struct ConversionReport: Sendable {
    let startedAt: Date
    let finishedAt: Date
    let entries: [ConversionEntry]
    let convertedCount: Int
    let emptyCount: Int
    let skippedCount: Int
    let failedCount: Int

    var totalCount: Int {
        entries.count
    }

    var duration: TimeInterval {
        finishedAt.timeIntervalSince(startedAt)
    }

    var summaryLine: String {
        "Converted \(convertedCount) of \(totalCount) files (Empty \(emptyCount), Skipped \(skippedCount), Failed \(failedCount))."
    }
}
