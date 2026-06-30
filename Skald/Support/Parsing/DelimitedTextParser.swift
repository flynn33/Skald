import Foundation

nonisolated final class DelimitedTextParser {
    func parse(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false

        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]

            if inQuotes {
                if char == "\"" {
                    let nextIndex = text.index(after: index)
                    if nextIndex < text.endIndex, text[nextIndex] == "\"" {
                        currentField.append("\"")
                        index = nextIndex
                    } else {
                        inQuotes = false
                    }
                } else {
                    currentField.append(char)
                }
            } else {
                if char == "\"" {
                    inQuotes = true
                } else if char == delimiter {
                    currentRow.append(currentField)
                    currentField = ""
                } else if char == "\n" {
                    currentRow.append(currentField)
                    rows.append(currentRow)
                    currentRow = []
                    currentField = ""
                } else if char == "\r" {
                    let nextIndex = text.index(after: index)
                    if nextIndex < text.endIndex, text[nextIndex] == "\n" {
                        index = nextIndex
                    }
                    currentRow.append(currentField)
                    rows.append(currentRow)
                    currentRow = []
                    currentField = ""
                } else {
                    currentField.append(char)
                }
            }

            index = text.index(after: index)
        }

        currentRow.append(currentField)
        if !currentRow.allSatisfy({ $0.isEmpty }) {
            rows.append(currentRow)
        }

        var trimmedRows: [[String]] = []
        for row in rows {
            let trimmedRow = row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if trimmedRow.allSatisfy({ $0.isEmpty }) {
                continue
            }
            trimmedRows.append(trimmedRow)
        }

        if let first = trimmedRows.first, let firstCell = first.first, firstCell.hasPrefix("\u{feff}") {
            trimmedRows[0][0] = String(firstCell.dropFirst())
        }

        return trimmedRows
    }
}
