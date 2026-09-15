import AppKit
import Foundation

nonisolated struct AttributedInputError: Error, LocalizedError {
    let code: String
    let summary: String
    var errorDescription: String? { "\(code): \(summary)" }
}

nonisolated final class AttributedDocumentConverter: DocumentConverter {
    let supportedExtensions = ["docx", "doc", "rtf", "rtfd", "odt", "html", "htm", "webarchive"]
    private let parser = AttributedTextParser()
    private let maximumHTMLBytes: Int
    private let maximumDocumentBytes: Int
    private let maximumPackageEntries: Int
    private let htmlTimeout: TimeInterval

    init(maximumHTMLBytes: Int = 8 * 1_024 * 1_024, maximumDocumentBytes: Int = 64 * 1_024 * 1_024, maximumPackageEntries: Int = 1_000, htmlTimeout: TimeInterval = 10) {
        self.maximumHTMLBytes = max(1, maximumHTMLBytes)
        self.maximumDocumentBytes = maximumDocumentBytes
        self.maximumPackageEntries = maximumPackageEntries
        self.htmlTimeout = max(1, htmlTimeout)
    }

    private func documentType(for ext: String) -> NSAttributedString.DocumentType? {
        switch ext.lowercased() {
        case "doc": return .docFormat
        case "docx": return .officeOpenXML
        case "rtf": return .rtf
        case "rtfd": return .rtfd
        case "odt": return .openDocument
        default: return nil
        }
    }

    func convert(at url: URL, to format: OutputFormat) throws -> String {
        try convertDetailed(at: url, to: format).output
    }

    func convertDetailed(at url: URL, to format: OutputFormat) throws -> ConverterOutcome {
        let sourceExtension = SourceFileDescriptor(url: url).fileExtension
        var warnings: [String] = []
        let blocks: [ReadableBlock]
        if ["html", "htm"].contains(sourceExtension) {
            let (html, hasTable) = try validatedHTML(at: url)
            let text = try OfflineHTMLService().loadText(html, timeout: htmlTimeout)
            blocks = PlainTextParser().parse(text)
            if hasTable { warnings.append("tableStructureNotExtracted") }
        } else if sourceExtension == "webarchive" {
            throw AttributedInputError(code: "externalResourceDenied", summary: "Web archives are not imported without a resource-isolated reader.")
        } else {
            guard let type = documentType(for: sourceExtension) else { throw ConversionError.unsupportedFormat }
            try BoundedInputReader.preflight(url, maximumBytes: maximumDocumentBytes, maximumEntries: maximumPackageEntries)
            let attributed = try NSAttributedString(url: url, options: [.documentType: type], documentAttributes: nil)
            warnings.append(contentsOf: unextractedFeatures(in: attributed))
            if ["doc", "docx", "odt"].contains(sourceExtension) {
                warnings.append("containerStructuresNotVerified")
            }
            blocks = parser.parse(attributed)
        }
        warnings = Array(Set(warnings)).sorted()
        let quality: ExtractionQuality = !warnings.isEmpty ? .partial : (blocks.isEmpty ? .empty : .complete)
        let output: String
        switch format {
        case .markdown:
            let body = ReadableOutputFormatter.markdownDocument(title: "Attributed document", blocks: blocks)
            output = warnings.isEmpty ? body : "_Extraction partial; warnings: \(warnings.joined(separator: ", "))._\n\n" + body
        case .json:
            output = try ReadableOutputFormatter.jsonDocument(
                fileName: url.lastPathComponent,
                sourceExtension: sourceExtension,
                blocks: blocks,
                extractionWarnings: warnings.isEmpty ? nil : warnings,
                schemaVersion: warnings.isEmpty ? "1.1" : "2.0"
            )
        }
        return ConverterOutcome(output: output, quality: quality, warnings: warnings)
    }

    private func validatedHTML(at url: URL) throws -> (String, Bool) {
        let data = try BoundedInputReader.read(url, maximumBytes: maximumHTMLBytes)
        guard let html = String(data: data, encoding: .utf8) else {
            throw AttributedInputError(code: "invalidHTML", summary: "HTML is not strict UTF-8.")
        }
        let allowed = Set(["html", "head", "body", "title", "h1", "h2", "h3", "h4", "h5", "h6", "p", "div", "span", "b", "strong", "i", "em", "u", "br", "ul", "ol", "li", "blockquote", "pre", "code", "table", "thead", "tbody", "tr", "td", "th"])
        let tagPattern = try NSRegularExpression(pattern: "<[^>]*>")
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = tagPattern.matches(in: html, range: range)
        var consumedOpenBrackets = 0
        var hasTable = false
        for match in matches {
            guard let swiftRange = Range(match.range, in: html) else { continue }
            let token = String(html[swiftRange])
            consumedOpenBrackets += token.filter({ $0 == "<" }).count
            var body = token.dropFirst().dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
            if body.hasPrefix("/") { body = String(body.dropFirst()) }
            if body.hasSuffix("/") { body = String(body.dropLast()) }
            body = body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard allowed.contains(body) else {
                throw AttributedInputError(code: "externalResourceDenied", summary: "HTML tags or attributes that may load resources are not accepted.")
            }
            hasTable = hasTable || ["table", "thead", "tbody", "tr", "td", "th"].contains(body)
        }
        guard html.filter({ $0 == "<" }).count == consumedOpenBrackets else {
            throw AttributedInputError(code: "invalidHTML", summary: "Malformed HTML markup is not accepted.")
        }
        return (html, hasTable)
    }

    func unextractedFeatures(in attributed: NSAttributedString) -> [String] {
        var warnings: [String] = []
        let range = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(.attachment, in: range, options: []) { value, _, _ in
            if value != nil && !warnings.contains("attachmentNotExtracted") { warnings.append("attachmentNotExtracted") }
        }
        attributed.enumerateAttribute(.paragraphStyle, in: range, options: []) { value, _, _ in
            if let style = value as? NSParagraphStyle, !style.textBlocks.isEmpty && !warnings.contains("tableStructureNotExtracted") {
                warnings.append("tableStructureNotExtracted")
            }
        }
        return warnings
    }
}
