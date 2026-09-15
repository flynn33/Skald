import Foundation

/// Converts simple INI / properties / env style configuration into the shared
/// readable model. `[section]` headers become nested objects; `key = value`
/// (or `key: value`) lines become string entries; `;` and `#` start comments.
nonisolated final class IniConverter: DocumentConverter {
    let supportedExtensions = ["ini", "cfg", "properties", "env"]
    private let maximumInputBytes: Int
    private let maximumRecords: Int
    private let maximumFieldScalars: Int

    init(maximumInputBytes: Int = 16 * 1_024 * 1_024, maximumRecords: Int = 100_000, maximumFieldScalars: Int = 1_000_000) {
        self.maximumInputBytes = maximumInputBytes
        self.maximumRecords = maximumRecords
        self.maximumFieldScalars = maximumFieldScalars
    }

    func convert(at url: URL, to format: OutputFormat) throws -> String {
        let text = try TextFileReader.read(url, maximumInputBytes: maximumInputBytes)
        let value = try parse(text)

        switch format {
        case .markdown:
            return ReadableOutputFormatter.markdownDocument(
                title: ReadableOutputFormatter.readableTitle(from: url),
                blocks: ReadableOutputFormatter.blocks(from: value)
            )
        case .json:
            do {
                return try ReadableOutputFormatter.jsonDocument(
                    fileName: url.lastPathComponent,
                    sourceExtension: SourceFileDescriptor(url: url).fileExtension,
                    blocks: [],
                    data: value
                )
            } catch {
                throw ConversionError.jsonSerializationFailed
            }
        }
    }

    private func parse(_ text: String) throws -> ReadableValue {
        guard maximumRecords > 0, maximumFieldScalars > 0 else {
            throw InputDiagnostic(code: "invalidLimitConfiguration", stage: "configure", summary: "INI limits must be positive.")
        }
        var rootEntries: [String: ReadableValue] = [:]
        var sections: [String: [String: ReadableValue]] = [:]
        var sectionOrder: [String] = []
        var currentSection: String? = nil

        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        for (index, rawLine) in lines.enumerated() {
            if Task.isCancelled { throw OutputPublicationError.cancelled }
            guard index < maximumRecords else {
                throw InputDiagnostic(code: "recordLimitExceeded", stage: "parse", record: index + 1,
                                      summary: "INI input exceeds the configured line limit.")
            }
            guard rawLine.unicodeScalars.count <= maximumFieldScalars else {
                throw InputDiagnostic(code: "fieldLimitExceeded", stage: "parse", record: index + 1,
                                      summary: "INI line exceeds the configured scalar limit.")
            }
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") {
                continue
            }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                let name = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    currentSection = name
                    if sections[name] == nil {
                        sections[name] = [:]
                        sectionOrder.append(name)
                    }
                }
                continue
            }

            guard let separatorIndex = firstSeparatorIndex(in: line) else {
                continue
            }
            let key = String(line[line.startIndex..<separatorIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }

            let unquoted = stripQuotes(value)
            if let section = currentSection {
                sections[section]?[key] = .string(unquoted)
            } else {
                rootEntries[key] = .string(unquoted)
            }
        }

        var object = rootEntries
        for name in sectionOrder {
            object[name] = .object(sections[name] ?? [:])
        }
        return .object(object)
    }

    private func firstSeparatorIndex(in line: String) -> String.Index? {
        let equals = line.firstIndex(of: "=")
        let colon = line.firstIndex(of: ":")
        switch (equals, colon) {
        case let (e?, c?):
            return e < c ? e : c
        case let (e?, nil):
            return e
        case let (nil, c?):
            return c
        default:
            return nil
        }
    }

    private func stripQuotes(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
            (value.hasPrefix("'") && value.hasSuffix("'")) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}
