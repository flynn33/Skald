import Foundation

nonisolated protocol DelimitedParsing {
    func parse(_ text: String, delimiter: Unicode.Scalar, chunkSize: Int) throws -> [[String]]
}

nonisolated final class DelimitedTextParser: DelimitedParsing {
    private enum State { case startField, unquoted, quoted, afterQuote }

    func parse(_ text: String, delimiter: Character) throws -> [[String]] {
        guard delimiter.unicodeScalars.count == 1, let scalar = delimiter.unicodeScalars.first else {
            throw DelimitedInputError(code: "invalidDelimiter", stage: "configure", summary: "Delimiter must be one Unicode scalar.")
        }
        return try parse(text, delimiter: scalar, chunkSize: 4_096)
    }

    func parse(_ text: String, delimiter: Unicode.Scalar, chunkSize: Int = 4_096) throws -> [[String]] {
        guard chunkSize > 0,
              delimiter != "\"", delimiter != "\r", delimiter != "\n", delimiter != "\0" else {
            throw DelimitedInputError(code: "invalidDelimiter", stage: "configure", summary: "Delimiter or chunk size is invalid.")
        }
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var state: State = .startField
        var recordStarted = false
        var pendingCR = false
        var line = 1
        var previousLineCR = false
        var scalarOffset = 0

        func finishField() {
            row.append(field)
            field = ""
            state = .startField
        }
        func finishRecord() {
            finishField()
            rows.append(row)
            row = []
            recordStarted = false
        }
        func malformed(_ summary: String) -> DelimitedInputError {
            DelimitedInputError(code: "malformedDelimitedText", stage: "parse", record: rows.count + 1, field: row.count + 1, line: line, scalarOffset: scalarOffset, summary: summary)
        }
        func consume(_ scalar: Unicode.Scalar) throws {
            scalarOffset += 1
            if scalar == "\r" { line += 1; previousLineCR = true }
            else if scalar == "\n" { if !previousLineCR { line += 1 }; previousLineCR = false }
            else { previousLineCR = false }

            if pendingCR {
                pendingCR = false
                if scalar == "\n" { return }
            }
            if state == .quoted {
                if scalar == "\"" { state = .afterQuote }
                else { field.unicodeScalars.append(scalar) }
                return
            }
            if state == .afterQuote, scalar == "\"" {
                field.unicodeScalars.append("\"")
                state = .quoted
                return
            }
            if scalar == delimiter {
                finishField()
                recordStarted = true
                return
            }
            if scalar == "\r" || scalar == "\n" {
                finishRecord()
                if scalar == "\r" { pendingCR = true }
                return
            }
            switch state {
            case .startField:
                recordStarted = true
                if scalar == "\"" { state = .quoted }
                else { field.unicodeScalars.append(scalar); state = .unquoted }
            case .unquoted:
                if scalar == "\"" { throw malformed("A quote appeared inside an unquoted field.") }
                field.unicodeScalars.append(scalar)
            case .afterQuote:
                throw malformed("Text followed a closing quote.")
            case .quoted:
                break
            }
        }

        var iterator = text.unicodeScalars.makeIterator()
        while true {
            var chunk: [Unicode.Scalar] = []
            chunk.reserveCapacity(min(chunkSize, 4_096))
            for _ in 0..<chunkSize {
                guard let scalar = iterator.next() else { break }
                chunk.append(scalar)
            }
            if chunk.isEmpty { break }
            for scalar in chunk { try consume(scalar) }
        }
        if state == .quoted { throw malformed("Quoted field was not closed before end of file.") }
        if recordStarted { finishRecord() }
        return rows
    }
}
