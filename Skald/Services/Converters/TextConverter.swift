import Foundation

nonisolated final class TextConverter: DocumentConverter {
    let supportedExtensions = ["txt", "md", "markdown", "mdown"]
    private let parser = PlainTextParser()
    private let maximumInputBytes: Int

    init(maximumInputBytes: Int = 16 * 1_024 * 1_024) { self.maximumInputBytes = maximumInputBytes }

    func convert(at url: URL, to format: OutputFormat) throws -> String {
        let data = try BoundedInputReader.read(url, maximumBytes: maximumInputBytes)
        guard let text = String(data: data, encoding: .utf8) else {
            throw InputDiagnostic(code: "invalidTextEncoding", stage: "decode", fileName: url.lastPathComponent,
                                  summary: "Text input is not strict UTF-8.")
        }
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
