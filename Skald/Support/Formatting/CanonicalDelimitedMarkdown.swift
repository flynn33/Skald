import Foundation

nonisolated enum CanonicalDelimitedMarkdown {
    static func render(_ table: CanonicalDelimitedTable, settings: AppliedDelimitedSettings?) throws -> String {
        var lines = ["# Delimited data", "", "Column IDs are stable; labels retain source text. JSON `null` means a missing field; `\"\"` means an explicit empty field. Record objects use the column IDs.", "", "## Columns", ""]
        try appendJSON(table.columns, to: &lines)
        for record in table.records {
            lines += ["", "### Record \(record.index) (\(record.fieldCount) fields)", ""]
            let values = Dictionary(uniqueKeysWithValues: zip(table.columns, record.cells).map { ($0.id, $1) })
            try appendJSON(values, to: &lines)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func appendJSON<T: Encodable>(_ value: T, to lines: inout [String]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard var json = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        // Keep source markup inert even in Markdown renderers that parse raw HTML
        // inside fences; JSON Unicode escapes recover the exact original text.
        for (literal, escape) in [("&", "\\u0026"), ("<", "\\u003C"), (">", "\\u003E")] {
            json = json.replacingOccurrences(of: literal, with: escape)
        }
        var longest = 0
        var run = 0
        for character in json {
            if character == "~" { run += 1; longest = max(longest, run) } else { run = 0 }
        }
        let fence = String(repeating: "~", count: max(3, longest + 1))
        lines += [fence + "json", json, fence]
    }
}
