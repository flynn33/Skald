import Foundation

nonisolated struct DelimitedConversion {
    let output: String
    let appliedSettings: AppliedDelimitedSettings
    let isEmpty: Bool
}

nonisolated final class DelimitedTextConverter: DocumentConverter {
    private struct DelimiterResolution { let scalar: Unicode.Scalar; let unconfirmed: Bool }
    let supportedExtensions = ["csv", "tsv"]
    private let decoder: TextDecoding
    private let parser: DelimitedParsing
    private let interpreter: DelimitedTextInterpreter

    init(decoder: TextDecoding = TextDecoder(), parser: DelimitedParsing = DelimitedTextParser(), interpreter: DelimitedTextInterpreter = DelimitedTextInterpreter()) {
        self.decoder = decoder
        self.parser = parser
        self.interpreter = interpreter
    }

    func convert(at url: URL, to format: OutputFormat) throws -> String {
        try convert(at: url, to: format, options: DelimitedOptions()).output
    }

    func convert(at url: URL, to format: OutputFormat, options: DelimitedOptions) throws -> DelimitedConversion {
        let decoded = try decoder.read(url, choice: options.encoding)
        let sourceExtension = SourceFileDescriptor(url: url).fileExtension
        var text = decoded.text
        let delimiterResolution = try resolveDelimiter(options.delimiter, text: text, sourceExtension: sourceExtension)
        let selectedDelimiter = delimiterResolution.scalar
        if options.allowSepPreamble, text.hasPrefix("sep=\(String(selectedDelimiter))") {
            let remainder = text.dropFirst(5)
            if remainder.hasPrefix("\r\n") || remainder.hasPrefix("\r") || remainder.hasPrefix("\n") {
                text = String(remainder.dropFirst())
            } else if remainder.isEmpty { text = "" }
        }
        let rows = try parser.parse(text, delimiter: selectedDelimiter, chunkSize: 4_096)
        let interpretation = interpreter.interpret(rows: rows, headerMode: options.header)
        let applied = AppliedDelimitedSettings(
            encoding: decoded.encoding,
            encodingProvenance: decoded.provenance,
            delimiter: String(selectedDelimiter),
            headerMode: options.header.rawValue,
            headerConfirmed: interpretation.headerConfirmed,
            diagnostics: interpretation.diagnostics.map(\.code) + (delimiterResolution.unconfirmed ? ["delimiterUnconfirmed"] : [])
        )
        guard !rows.isEmpty else {
            return DelimitedConversion(output: try emptyOutput(for: url, format: format, settings: applied), appliedSettings: applied, isEmpty: true)
        }
        let columns = interpretation.originalHeader ?? generateColumns(count: rows[0].count)
        let dataRows = interpretation.dataRows
        let table = ReadableTable(title: nil, columns: columns, rows: dataRows)
        let dataValue = buildDataValue(columns: columns, rows: dataRows, hasHeader: interpretation.headerConfirmed)
        let output: String
        switch format {
        case .markdown:
            let body = ReadableOutputFormatter.markdownDocument(
                title: ReadableOutputFormatter.readableTitle(from: url), blocks: [], tables: [table]
            )
            output = markdownSettings(applied) + body
        case .json:
            output = try ReadableOutputFormatter.jsonDocument(
                fileName: url.lastPathComponent,
                sourceExtension: sourceExtension,
                blocks: [], tables: [table], data: dataValue,
                importSettings: applied, schemaVersion: "1.2"
            )
        }
        return DelimitedConversion(output: output, appliedSettings: applied, isEmpty: false)
    }

    private func emptyOutput(for url: URL, format: OutputFormat, settings: AppliedDelimitedSettings) throws -> String {
        switch format {
        case .markdown:
            return markdownSettings(settings) + ReadableOutputFormatter.markdownDocument(title: ReadableOutputFormatter.readableTitle(from: url), blocks: [])
        case .json:
            return try ReadableOutputFormatter.jsonDocument(fileName: url.lastPathComponent, sourceExtension: SourceFileDescriptor(url: url).fileExtension, blocks: [], importSettings: settings, schemaVersion: "1.2")
        }
    }

    private func markdownSettings(_ settings: AppliedDelimitedSettings) -> String {
        let scalar = settings.delimiter.unicodeScalars.first?.value ?? 0
        let point = String(format: "U+%04X", scalar)
        let warnings = settings.diagnostics.isEmpty ? "" : "; warnings: \(settings.diagnostics.joined(separator: ", "))"
        return "_Import settings: \(settings.encoding), delimiter \(point), header \(settings.headerMode)\(warnings)._\n\n"
    }

    private func resolveDelimiter(_ choice: DelimiterChoice, text: String, sourceExtension: String) throws -> DelimiterResolution {
        switch choice {
        case .comma: return DelimiterResolution(scalar: ",", unconfirmed: false)
        case .tab: return DelimiterResolution(scalar: "\t", unconfirmed: false)
        case .semicolon: return DelimiterResolution(scalar: ";", unconfirmed: false)
        case .custom(let value):
            guard value.unicodeScalars.count == 1, let scalar = value.unicodeScalars.first,
                  scalar != "\"", scalar != "\r", scalar != "\n", scalar != "\0" else {
                throw DelimitedInputError(code: "invalidDelimiter", stage: "configure", summary: "Custom delimiter must be one non-quote, non-newline Unicode scalar.")
            }
            return DelimiterResolution(scalar: scalar, unconfirmed: false)
        case .automatic:
            if sourceExtension == "tsv" { return DelimiterResolution(scalar: "\t", unconfirmed: false) }
            if text.hasPrefix("sep=;\n") || text.hasPrefix("sep=;\r") { return DelimiterResolution(scalar: ";", unconfirmed: false) }
            let sample = String(text.prefix(16_384))
            var candidates: [Unicode.Scalar] = []
            let choices: [Unicode.Scalar] = [",", "\t", ";"]
            for scalar in choices {
                guard let rows = try? parser.parse(sample, delimiter: scalar, chunkSize: 4_096) else { continue }
                let widths = rows.prefix(8).map(\.count)
                if widths.count >= 2, let first = widths.first, first >= 2,
                   widths.allSatisfy({ $0 == first }) {
                    candidates.append(scalar)
                }
            }
            if candidates.count == 1, let sole = candidates.first { return DelimiterResolution(scalar: sole, unconfirmed: false) }
            return DelimiterResolution(scalar: ",", unconfirmed: true)
        }
    }

    private func generateColumns(count: Int) -> [String] {
        (1...max(1, count)).map { "Column \($0)" }
    }

    private func buildDataValue(columns: [String], rows: [[String]], hasHeader: Bool) -> ReadableValue {
        if hasHeader {
            let objects: [ReadableValue] = rows.map { row in
                var dict: [String: ReadableValue] = [:]
                for (index, column) in columns.enumerated() {
                    let value = index < row.count ? row[index] : ""
                    dict[column] = .string(value)
                }
                return .object(dict)
            }
            return .array(objects)
        }
        return .array(rows.map { .array($0.map { .string($0) }) })
    }
}
