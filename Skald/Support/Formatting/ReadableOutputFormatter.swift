import Foundation

nonisolated enum ReadableOutputFormatter {
    private static let markdownWrapWidth = 90

    static func markdownDocument(
        title: String,
        blocks: [ReadableBlock],
        tables: [ReadableTable] = [],
        data: ReadableValue? = nil
    ) -> String {
        // When the document already opens with its own heading, use that as the
        // top-level heading instead of prepending a redundant filename-derived
        // title (e.g. "# Sample Text" above "## Sample Document").
        let documentHasOwnTitle = blocks.first?.type == .heading
        let headingBaseLevel = documentHasOwnTitle ? 1 : 2

        var sections: [[String]] = []

        if !blocks.isEmpty {
            sections.append(renderMarkdownBody(blocks: blocks, headingBaseLevel: headingBaseLevel))
        }

        if !tables.isEmpty {
            sections.append(renderMarkdownTables(tables, headingBaseLevel: headingBaseLevel))
        }

        if blocks.isEmpty, tables.isEmpty, let dataValue = data {
            let dataBlocks = ReadableOutputFormatter.blocks(from: dataValue)
            sections.append(renderMarkdownBody(blocks: dataBlocks, headingBaseLevel: headingBaseLevel))
        }

        var lines: [String] = documentHasOwnTitle ? [] : ["# \(title)"]
        for section in sections where !section.isEmpty {
            if !lines.isEmpty {
                lines.append("")
            }
            lines.append(contentsOf: section)
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    static func markdownDocument(title: String, pages: [[ReadableBlock]]) -> String {
        var outputLines: [String] = ["# \(title)"]

        for (index, pageBlocks) in pages.enumerated() {
            outputLines.append("")
            outputLines.append("## Page \(index + 1)")
            outputLines.append("")

            if pageBlocks.isEmpty {
                outputLines.append("_No extractable text on this page._")
                continue
            }

            let bodyLines = renderMarkdownBody(blocks: pageBlocks, headingBaseLevel: 3)
            outputLines.append(contentsOf: bodyLines)
        }

        return outputLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    static func jsonDocument(
        fileName: String,
        sourceExtension: String,
        blocks: [ReadableBlock],
        tables: [ReadableTable] = [],
        data: ReadableValue? = nil
    ) throws -> String {
        let blockCount = blocks.count
        let tableCount = tables.isEmpty ? nil : tables.count
        let payload = ReadableDocument(
            version: "1.1",
            source: ReadableSource(
                fileName: fileName,
                fileExtension: sourceExtension.lowercased(),
                convertedAt: iso8601Now()
            ),
            summary: ReadableSummary(
                blockCount: blockCount,
                pageCount: nil,
                tableCount: tableCount,
                dataPresent: data == nil ? nil : true
            ),
            content: ReadableContent(
                blocks: blocks.isEmpty ? nil : blocks,
                pages: nil,
                tables: tables.isEmpty ? nil : tables,
                data: data
            )
        )

        return try encode(payload)
    }

    static func jsonDocument(fileName: String, sourceExtension: String, pages: [[ReadableBlock]]) throws -> String {
        let readablePages = pages.enumerated().map { index, pageBlocks in
            ReadablePage(
                page: index + 1,
                blockCount: pageBlocks.count,
                blocks: pageBlocks
            )
        }

        let totalBlockCount = readablePages.reduce(0) { $0 + $1.blockCount }
        let payload = ReadableDocument(
            version: "1.1",
            source: ReadableSource(
                fileName: fileName,
                fileExtension: sourceExtension.lowercased(),
                convertedAt: iso8601Now()
            ),
            summary: ReadableSummary(
                blockCount: totalBlockCount,
                pageCount: readablePages.count,
                tableCount: nil,
                dataPresent: nil
            ),
            content: ReadableContent(
                blocks: nil,
                pages: readablePages,
                tables: nil,
                data: nil
            )
        )

        return try encode(payload)
    }

    static func readableTitle(from fileURL: URL) -> String {
        let stem = fileURL.deletingPathExtension().lastPathComponent
        let words = stem
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map(String.init)

        guard !words.isEmpty else {
            return stem
        }

        return words.map(capitalizeWordKeepingAcronyms).joined(separator: " ")
    }

    static func blocks(from value: ReadableValue) -> [ReadableBlock] {
        var blocks: [ReadableBlock] = []
        var order = 1

        func addListItem(_ text: String, depth: Int) {
            blocks.append(
                ReadableBlock(
                    order: order,
                    type: .listItem,
                    text: collapseWhitespace(in: text),
                    headingLevel: nil,
                    listStyle: .unordered,
                    listDepth: max(0, depth),
                    listIndex: nil
                )
            )
            order += 1
        }

        func render(_ value: ReadableValue, key: String?, depth: Int) {
            switch value {
            case .object(let dict):
                let sortedKeys = dict.keys.sorted()
                if let key = key {
                    addListItem("\(key):", depth: depth)
                }
                for nestedKey in sortedKeys {
                    if let nestedValue = dict[nestedKey] {
                        render(nestedValue, key: nestedKey, depth: depth + (key == nil ? 0 : 1))
                    }
                }

            case .array(let array):
                let itemDepth = depth + (key == nil ? 0 : 1)
                if let key = key {
                    addListItem("\(key):", depth: depth)
                }
                for (index, item) in array.enumerated() {
                    switch item {
                    case .object, .array:
                        // Give each container element its own boundary so the
                        // fields of distinct records don't merge into one list.
                        addListItem("Item \(index + 1):", depth: itemDepth)
                        render(item, key: nil, depth: itemDepth + 1)
                    default:
                        render(item, key: nil, depth: itemDepth)
                    }
                }

            case .string(let stringValue):
                let valueText = stringValue.replacingOccurrences(of: "\n", with: " ")
                if let key = key {
                    addListItem("\(key): \(valueText)", depth: depth)
                } else {
                    addListItem(valueText, depth: depth)
                }

            case .number(let numberValue):
                let valueText = formatNumber(numberValue)
                if let key = key {
                    addListItem("\(key): \(valueText)", depth: depth)
                } else {
                    addListItem(valueText, depth: depth)
                }

            case .bool(let boolValue):
                let valueText = boolValue ? "true" : "false"
                if let key = key {
                    addListItem("\(key): \(valueText)", depth: depth)
                } else {
                    addListItem(valueText, depth: depth)
                }

            case .null:
                if let key = key {
                    addListItem("\(key): null", depth: depth)
                } else {
                    addListItem("null", depth: depth)
                }
            }
        }

        render(value, key: nil, depth: 0)
        return blocks
    }

    private static func renderMarkdownBody(blocks: [ReadableBlock], headingBaseLevel: Int) -> [String] {
        var lines: [String] = []
        var previousBlockWasList = false

        for block in blocks {
            switch block.type {
            case .heading:
                if !lines.isEmpty && lines.last != "" {
                    lines.append("")
                }
                let headingLevel = max(1, min(6, headingBaseLevel + (block.headingLevel ?? 1) - 1))
                let prefix = String(repeating: "#", count: headingLevel)
                lines.append("\(prefix) \(block.text)")
                lines.append("")
                previousBlockWasList = false

            case .paragraph:
                if !lines.isEmpty && lines.last != "" {
                    lines.append("")
                }
                lines.append(contentsOf: wrapText(block.text, width: markdownWrapWidth, initialIndent: "", subsequentIndent: ""))
                previousBlockWasList = false

            case .listItem:
                if !previousBlockWasList && !lines.isEmpty && lines.last != "" {
                    lines.append("")
                }
                let depth = max(0, block.listDepth ?? 0)
                let indent = String(repeating: "  ", count: depth)
                let marker = listMarker(for: block)
                let prefix = indent + marker
                let subsequentIndent = String(repeating: " ", count: prefix.count)
                lines.append(contentsOf: wrapText(block.text, width: markdownWrapWidth, initialIndent: prefix, subsequentIndent: subsequentIndent))
                previousBlockWasList = true

            case .code:
                // Verbatim fenced code: never wrapped or whitespace-collapsed, so
                // indentation and line breaks of source/config/log files survive.
                if !lines.isEmpty && lines.last != "" {
                    lines.append("")
                }
                lines.append("```")
                for codeLine in block.text.components(separatedBy: "\n") {
                    lines.append(codeLine)
                }
                lines.append("```")
                lines.append("")
                previousBlockWasList = false
            }
        }

        return trimTrailingBlankLines(lines)
    }

    private static func renderMarkdownTables(_ tables: [ReadableTable], headingBaseLevel: Int) -> [String] {
        var lines: [String] = []
        for table in tables {
            if let title = table.title, !title.isEmpty {
                if !lines.isEmpty && lines.last != "" {
                    lines.append("")
                }
                let prefix = String(repeating: "#", count: max(1, min(6, headingBaseLevel)))
                lines.append("\(prefix) \(title)")
                lines.append("")
            } else if !lines.isEmpty {
                lines.append("")
            }

            lines.append(contentsOf: renderMarkdownTable(table))
        }
        return trimTrailingBlankLines(lines)
    }

    private static func renderMarkdownTable(_ table: ReadableTable) -> [String] {
        let columns = table.columns
        let columnCount = columns.count
        guard columnCount > 0 else {
            return []
        }

        var widths = columns.map { $0.count }
        for row in table.rows {
            for index in 0..<columnCount {
                let cell = index < row.count ? row[index] : ""
                widths[index] = max(widths[index], cell.count)
            }
        }

        let header = "| " + zip(columns, widths).map { pad($0.0, width: $0.1) }.joined(separator: " | ") + " |"
        let separator = "| " + widths.map { String(repeating: "-", count: max(3, $0)) }.joined(separator: " | ") + " |"

        var lines: [String] = [header, separator]
        for row in table.rows {
            let rowCells = (0..<columnCount).map { index -> String in
                let cell = index < row.count ? row[index] : ""
                return pad(cell, width: widths[index])
            }
            lines.append("| " + rowCells.joined(separator: " | ") + " |")
        }

        return lines
    }

    private static func listMarker(for block: ReadableBlock) -> String {
        guard block.listStyle == .ordered else {
            return "- "
        }
        if let index = block.listIndex {
            return "\(index). "
        }
        return "1. "
    }

    private static func wrapText(
        _ text: String,
        width: Int,
        initialIndent: String,
        subsequentIndent: String
    ) -> [String] {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else {
            return []
        }

        let normalizedWidth = max(width, initialIndent.count + 10)
        var lines: [String] = []
        var currentLine = initialIndent

        for word in words {
            let wordText = String(word)
            if currentLine.count == initialIndent.count {
                currentLine += wordText
                continue
            }

            if currentLine.count + 1 + wordText.count <= normalizedWidth {
                currentLine += " " + wordText
            } else {
                lines.append(currentLine)
                currentLine = subsequentIndent + wordText
            }
        }

        if !currentLine.isEmpty {
            lines.append(currentLine)
        }

        return lines
    }

    private static func trimTrailingBlankLines(_ lines: [String]) -> [String] {
        var trimmed = lines
        while trimmed.last == "" {
            trimmed.removeLast()
        }
        return trimmed
    }

    private static func pad(_ text: String, width: Int) -> String {
        if text.count >= width {
            return text
        }
        return text + String(repeating: " ", count: width - text.count)
    }

    private static func iso8601Now() -> String {
        return ISO8601DateFormatter().string(from: Date())
    }

    private static func encode(_ document: ReadableDocument) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw ConversionError.jsonSerializationFailed
        }
        return jsonString
    }

    private static func collapseWhitespace(in text: String) -> String {
        return text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func capitalizeWordKeepingAcronyms(_ word: String) -> String {
        guard word.count > 1 else { return word.uppercased() }
        if word.allSatisfy(\.isUppercase) {
            return word
        }
        return word.prefix(1).uppercased() + word.dropFirst().lowercased()
    }

    private static func formatNumber(_ value: Double) -> String {
        if value.rounded(.towardZero) == value {
            return String(format: "%.0f", value)
        }
        return String(value)
    }
}
