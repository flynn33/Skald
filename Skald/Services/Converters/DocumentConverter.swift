import Foundation

nonisolated protocol DocumentConverter {
    var supportedExtensions: [String] { get }
    func convert(at url: URL, to format: OutputFormat) throws -> String
    func convertDetailed(at url: URL, to format: OutputFormat) throws -> ConverterOutcome
}

nonisolated enum ExtractionQuality: Equatable {
    case complete
    case empty
    case partial
}

nonisolated struct ConverterOutcome {
    let output: String
    let quality: ExtractionQuality
    let warnings: [String]
}

extension DocumentConverter {
    nonisolated func convertDetailed(at url: URL, to format: OutputFormat) throws -> ConverterOutcome {
        ConverterOutcome(output: try convert(at: url, to: format), quality: .complete, warnings: [])
    }
}
