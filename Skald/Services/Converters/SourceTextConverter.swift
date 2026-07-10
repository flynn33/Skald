import Foundation

/// Catch-all converter for an explicit allow-list of text-based formats that have
/// no native structural parser (source code, logs, YAML/TOML, etc.). Content is
/// preserved verbatim inside a fenced code block (Markdown) or a single code
/// block whose `text` holds the exact file contents (JSON), so indentation and
/// line breaks are never lost.
nonisolated final class SourceTextConverter: DocumentConverter {
    let supportedExtensions = [
        "yaml", "yml", "toml", "conf", "log",
        "swift", "py", "js", "mjs", "cjs", "ts", "tsx", "jsx",
        "java", "kt", "kts", "c", "h", "cpp", "cc", "cxx", "hpp",
        "cs", "rb", "go", "rs", "sh", "bash", "zsh", "sql",
        "css", "scss", "less", "php", "pl", "r", "lua", "dart",
        "scala", "groovy", "gradle", "tex", "rst", "adoc", "org",
        "vue", "svelte"
    ]

    func convert(at url: URL, to format: OutputFormat) throws -> String {
        let raw = try TextFileReader.read(url)
        let content = raw
        let block = ReadableBlock(
            order: 1,
            type: .code,
            text: content,
            headingLevel: nil,
            listStyle: nil,
            listDepth: nil,
            listIndex: nil
        )

        switch format {
        case .markdown:
            return ReadableOutputFormatter.markdownDocument(
                title: ReadableOutputFormatter.readableTitle(from: url),
                blocks: [block]
            )
        case .json:
            do {
                return try ReadableOutputFormatter.jsonDocument(
                    fileName: url.lastPathComponent,
                    sourceExtension: SourceFileDescriptor(url: url).fileExtension,
                    blocks: [block]
                )
            } catch {
                throw ConversionError.jsonSerializationFailed
            }
        }
    }
}
