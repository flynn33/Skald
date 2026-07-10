import Foundation

nonisolated final class TextConverter: DocumentConverter {
    let supportedExtensions = ["txt", "md", "markdown", "mdown"]
    private let parser = PlainTextParser()

    func convert(at url: URL, to format: OutputFormat) throws -> String {
        let text = try String(contentsOf: url, encoding: .utf8)
        let blocks = parser.parse(text)

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
                    sourceExtension: SourceFileDescriptor(url: url).fileExtension,
                    blocks: blocks
                )
            } catch {
                throw ConversionError.jsonSerializationFailed
            }
        }
    }
}
