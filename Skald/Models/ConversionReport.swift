import Foundation

nonisolated enum ConversionStatus: String, Sendable {
    case converted
    case partial
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
    let outputURLs: [URL]

    var outputURL: URL? {
        outputURLs.first
    }

    init(fileName: String, fileExtension: String, status: ConversionStatus, message: String?, outputURLs: [URL]) {
        self.fileName = fileName
        self.fileExtension = fileExtension
        self.status = status
        self.message = message
        self.outputURLs = outputURLs
    }

    init(fileName: String, fileExtension: String, status: ConversionStatus, message: String?, outputURL: URL?) {
        self.init(fileName: fileName, fileExtension: fileExtension, status: status, message: message,
                  outputURLs: outputURL.map { [$0] } ?? [])
    }
}

nonisolated struct ConversionReport: Sendable {
    let startedAt: Date
    let finishedAt: Date
    let entries: [ConversionEntry]
    let plannedCount: Int
    let convertedCount: Int
    let partialCount: Int
    let emptyCount: Int
    let skippedCount: Int
    let failedCount: Int
    let wasCancelled: Bool

    var totalCount: Int {
        entries.count
    }

    var duration: TimeInterval {
        finishedAt.timeIntervalSince(startedAt)
    }

    var summaryLine: String {
        let prefix = wasCancelled ? "Cancelled after" : "Converted"
        return "\(prefix) \(convertedCount) of \(plannedCount) planned inputs (Partial \(partialCount), Empty \(emptyCount), Skipped \(skippedCount), Failed \(failedCount))."
    }
}
