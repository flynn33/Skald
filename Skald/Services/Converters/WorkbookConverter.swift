import Foundation

nonisolated final class WorkbookConverter: DocumentConverter {
    let supportedExtensions = ["xlsx", "xls", "ods"]
    private let limits: ResourceLimits

    init(limits: ResourceLimits = ResourceLimits()) { self.limits = limits }

    func convert(at url: URL, to format: OutputFormat) throws -> String {
        try convertDetailed(at: url, to: format).output
    }

    func convertDetailed(at url: URL, to format: OutputFormat) throws -> ConverterOutcome {
        let fileExtension = SourceFileDescriptor(url: url).fileExtension
        let workbook: WorkbookDocument
        switch fileExtension {
        case "xlsx": workbook = try XLSXWorkbookReader(limits: limits).read(url)
        case "xls": workbook = try BIFF8WorkbookReader(limits: limits).read(url)
        case "ods": workbook = try ODSWorkbookReader(limits: limits).read(url)
        default: throw ConversionError.unsupportedFormat
        }
        let output = try workbook.output(format)
        let quality: ExtractionQuality = !workbook.warnings.isEmpty ? .partial :
            (workbook.sheets.allSatisfy { $0.cells.isEmpty } ? .empty : .complete)
        return ConverterOutcome(output: output, quality: quality, warnings: workbook.warnings)
    }
}
