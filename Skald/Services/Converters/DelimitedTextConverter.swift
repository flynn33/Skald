import Foundation

nonisolated final class DelimitedTextConverter: DocumentConverter {
    let supportedExtensions = ["csv", "tsv"]
    private let parser = DelimitedTextParser()

    func convert(at url: URL, to format: OutputFormat) throws -> String {
        let text = try String(contentsOf: url, encoding: .utf8)
        let delimiter: Character = url.pathExtension.lowercased() == "tsv" ? "\t" : ","
        let rows = parser.parse(text, delimiter: delimiter)

        guard !rows.isEmpty else {
            return emptyOutput(for: url, format: format)
        }

        let headerRow = rows[0]
        let secondRow = rows.count > 1 ? rows[1] : nil
        let hasHeader = looksLikeHeader(firstRow: headerRow, secondRow: secondRow)

        let columns = hasHeader ? headerRow : generateColumns(count: headerRow.count)
        let dataRows = hasHeader ? Array(rows.dropFirst()) : rows

        let table = ReadableTable(title: nil, columns: columns, rows: dataRows)
        let dataValue = buildDataValue(columns: columns, rows: dataRows, hasHeader: hasHeader)

        switch format {
        case .markdown:
            return ReadableOutputFormatter.markdownDocument(
                title: ReadableOutputFormatter.readableTitle(from: url),
                blocks: [],
                tables: [table]
            )
        case .json:
            do {
                return try ReadableOutputFormatter.jsonDocument(
                    fileName: url.lastPathComponent,
                    sourceExtension: url.pathExtension,
                    blocks: [],
                    tables: [table],
                    data: dataValue
                )
            } catch {
                throw ConversionError.jsonSerializationFailed
            }
        }
    }

    private func emptyOutput(for url: URL, format: OutputFormat) -> String {
        switch format {
        case .markdown:
            return ReadableOutputFormatter.markdownDocument(
                title: ReadableOutputFormatter.readableTitle(from: url),
                blocks: []
            )
        case .json:
            return (try? ReadableOutputFormatter.jsonDocument(
                fileName: url.lastPathComponent,
                sourceExtension: url.pathExtension,
                blocks: []
            )) ?? "{}"
        }
    }

    private func looksLikeHeader(firstRow: [String], secondRow: [String]?) -> Bool {
        let firstScore = rowScore(firstRow)
        let secondScore = secondRow.map(rowScore) ?? (alpha: 0, numeric: 0)

        if firstScore.alpha == 0, firstScore.numeric > 0 {
            return false
        }

        if firstScore.alpha >= firstScore.numeric, firstScore.alpha > 0 {
            if secondScore.numeric >= secondScore.alpha {
                return true
            }
            return true
        }

        return false
    }

    private func rowScore(_ row: [String]) -> (alpha: Int, numeric: Int) {
        var alpha = 0
        var numeric = 0

        for cell in row {
            let trimmed = cell.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.rangeOfCharacter(from: .letters) != nil {
                alpha += 1
            } else if Double(trimmed) != nil {
                numeric += 1
            }
        }

        return (alpha, numeric)
    }

    private func generateColumns(count: Int) -> [String] {
        return (1...max(1, count)).map { "Column \($0)" }
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

        let arrays: [ReadableValue] = rows.map { row in
            .array(row.map { .string($0) })
        }
        return .array(arrays)
    }
}
