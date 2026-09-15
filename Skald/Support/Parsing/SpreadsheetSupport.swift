import Foundation

nonisolated enum SpreadsheetCoordinate {
    static func parse(_ text: String, maximumRows: Int, maximumColumns: Int) throws -> (row: Int, column: Int) {
        var column = 0
        var position = text.startIndex
        while position < text.endIndex, let ascii = text[position].unicodeScalars.first?.value, ascii >= 65, ascii <= 90 {
            let value = Int(ascii - 64)
            guard column <= (maximumColumns - value) / 26 else {
                throw InputDiagnostic(code: "spreadsheetColumnLimitExceeded", stage: "parse", summary: "Cell coordinate exceeds the configured column limit.")
            }
            column = column * 26 + value
            position = text.index(after: position)
        }
        guard column > 0, position < text.endIndex,
              let row = Int(text[position...]), row > 0, row <= maximumRows,
              text[position...].allSatisfy({ character in
                  guard let value = character.unicodeScalars.first?.value else { return false }
                  return value >= 48 && value <= 57
              }) else {
            throw InputDiagnostic(code: "invalidCellCoordinate", stage: "parse", summary: "Spreadsheet cell coordinate is invalid or out of bounds.")
        }
        return (row, column)
    }

    static func make(row: Int, column: Int) -> String {
        var value = column
        var letters = ""
        while value > 0 {
            value -= 1
            letters.insert(Character(Unicode.Scalar(65 + value % 26)!), at: letters.startIndex)
            value /= 26
        }
        return letters + String(row)
    }
}

nonisolated enum SpreadsheetDate {
    static func excelSerial(_ lexeme: String, epoch1904: Bool) -> String? {
        guard let decimal = Decimal(string: lexeme, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        let number = NSDecimalNumber(decimal: decimal).doubleValue
        guard number.isFinite, number >= 0, number < 3_000_000 else { return nil }
        let whole = Int(floor(number))
        if !epoch1904, whole == 60 { return "1900-02-29 (workbook leap-day convention)" }
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = epoch1904 ? 1904 : 1899
        components.month = epoch1904 ? 1 : 12
        components.day = epoch1904 ? 1 : 31
        guard let base = calendar.date(from: components) else { return nil }
        let adjusted = !epoch1904 && whole > 60 ? number - 1 : number
        let date = base.addingTimeInterval(adjusted * 86_400)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.string(from: date)
    }
}
