import PDFKit
import Foundation

nonisolated final class PDFConverter: DocumentConverter {
    let supportedExtensions = ["pdf"]
    private let parser = PDFTextParser()

    func convert(at url: URL, to format: OutputFormat) throws -> String {
        guard let pdfDocument = PDFDocument(url: url) else {
            throw ConversionError.invalidDocument
        }

        let pages = parser.parsePages(from: pdfDocument)

        switch format {
        case .markdown:
            return ReadableOutputFormatter.markdownDocument(
                title: ReadableOutputFormatter.readableTitle(from: url),
                pages: pages
            )

        case .json:
            do {
                return try ReadableOutputFormatter.jsonDocument(
                    fileName: url.lastPathComponent,
                    sourceExtension: SourceFileDescriptor(url: url).fileExtension,
                    pages: pages
                )
            } catch {
                throw ConversionError.jsonSerializationFailed
            }
        }
    }
}
