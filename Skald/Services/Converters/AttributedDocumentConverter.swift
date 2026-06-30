import Foundation
import AppKit

nonisolated final class AttributedDocumentConverter: DocumentConverter {
    let supportedExtensions = ["docx", "doc", "rtf", "rtfd", "odt", "html", "htm", "webarchive"]
    private let parser = AttributedTextParser()

    private func documentType(for ext: String) -> NSAttributedString.DocumentType? {
        switch ext.lowercased() {
        case "doc": return .docFormat
        case "docx": return .officeOpenXML
        case "rtf": return .rtf
        case "rtfd": return .rtfd
        case "odt": return .openDocument
        case "html", "htm": return .html
        case "webarchive": return .webArchive
        default: return nil
        }
    }

    func convert(at url: URL, to format: OutputFormat) throws -> String {
        let sourceExtension = url.pathExtension.lowercased()
        guard let docType = documentType(for: sourceExtension) else {
            throw ConversionError.unsupportedFormat
        }

        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: docType]
        let attrString = try NSAttributedString(url: url, options: options, documentAttributes: nil)
        let blocks = parser.parse(attrString)

        switch format {
        case .markdown:
            return ReadableOutputFormatter.markdownDocument(
                title: ReadableOutputFormatter.readableTitle(from: url),
                blocks: blocks
            )
        case .json:
            do {
                return try ReadableOutputFormatter.jsonDocument(
                    fileName: url.lastPathComponent,
                    sourceExtension: sourceExtension,
                    blocks: blocks
                )
            } catch {
                throw ConversionError.jsonSerializationFailed
            }
        }
    }
}
