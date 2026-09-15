import Foundation

nonisolated struct WorkbookCell: Codable {
    let coordinate: String
    let type: String
    let text: String?
    let numericLexeme: String?
    let formula: String?
    let cachedValue: String?
    let cacheStatus: String?
    let dateValue: String?
    let dateEpoch: String?
    let timezone: String?
    let styleIndex: Int?
}

nonisolated struct WorkbookSheet: Codable {
    let index: Int
    let name: String
    let cells: [WorkbookCell]
    let mergedRanges: [String]
}

nonisolated struct WorkbookDocument: Codable {
    let version: String
    let sourceFormat: String
    let fileName: String
    let sheets: [WorkbookSheet]
    let warnings: [String]

    func output(_ format: OutputFormat) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let encoded = try encoder.encode(self)
        guard let json = String(data: encoded, encoding: .utf8) else {
            throw InputDiagnostic(code: "outputSerializationFailed", stage: "render", summary: "Workbook output could not be encoded.")
        }
        if format == .json { return json + "\n" }
        var markdown: [String] = ["# Workbook", "", "_Format: \(sourceFormat); sheets: \(sheets.count)._", ""]
        for sheet in sheets {
            markdown += ["## Worksheet \(sheet.index)", ""]
            let summary: [String: Any] = ["name": sheet.name, "mergedRanges": sheet.mergedRanges]
            let summaryBytes = try JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys])
            let summaryText = String(decoding: summaryBytes, as: UTF8.self)
            markdown += [fence(summaryText) + "json", summaryText, fence(summaryText), ""]
            for cell in sheet.cells {
                let lineBytes = try encoder.encode(cell)
                let line = String(decoding: lineBytes, as: UTF8.self)
                markdown += ["### \(cell.coordinate)", "", fence(line) + "json", line, fence(line), ""]
            }
        }
        if !warnings.isEmpty {
            markdown += ["_Extraction warnings: \(warnings.joined(separator: ", "))._", ""]
        }
        return markdown.joined(separator: "\n") + "\n"
    }

    private func fence(_ text: String) -> String {
        var current = 0
        var longest = 0
        for character in text {
            if character == "~" { current += 1; longest = max(longest, current) }
            else { current = 0 }
        }
        return String(repeating: "~", count: max(3, longest + 1))
    }
}
