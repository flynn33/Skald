import Foundation

nonisolated protocol DelimitedParsing {
    func parse(_ text: String, delimiter: Unicode.Scalar, chunkSize: Int) throws -> [[String]]
}

nonisolated final class DelimitedTextParser: DelimitedParsing {
    private enum State { case startField, unquoted, quoted, afterQuote }
    private let maximumRecords: Int
    private let maximumColumns: Int
    private let maximumCells: Int
    private let maximumFieldScalars: Int

    init(maximumRecords: Int = 100_000, maximumColumns: Int = 1_024, maximumCells: Int = 250_000, maximumFieldScalars: Int = 1_000_000) {
        self.maximumRecords = maximumRecords
        self.maximumColumns = maximumColumns
        self.maximumCells = maximumCells
        self.maximumFieldScalars = maximumFieldScalars
    }

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
        guard maximumRecords > 0, maximumColumns > 0, maximumCells > 0, maximumFieldScalars > 0 else {
            throw DelimitedInputError(code: "invalidLimitConfiguration", stage: "configure", summary: "Delimited limits must be positive.")
        }
        var rows: [[String]] = []
        var cells = 0
        var row: [String] = []
        var field = ""
        var fieldScalars = 0
        var state: State = .startField
        var recordStarted = false
        var pendingCR = false
        var line = 1
        var previousLineCR = false
        var scalarOffset = 0

        func limit(_ code: String, _ summary: String) -> DelimitedInputError {
            DelimitedInputError(code: code, stage: "parse", record: rows.count + 1,
                                field: row.count + 1, line: line, scalarOffset: scalarOffset, summary: summary)
        }
        func appendFieldScalar(_ scalar: Unicode.Scalar) throws {
            guard fieldScalars < maximumFieldScalars else {
                throw limit("fieldLimitExceeded", "Field exceeds the configured scalar limit.")
            }
            field.unicodeScalars.append(scalar)
            fieldScalars += 1
        }
        func finishField() throws {
            guard row.count < maximumColumns else {
                throw limit("columnLimitExceeded", "Record exceeds the configured column limit.")
            }
            guard cells < maximumCells else {
                throw limit("cellLimitExceeded", "Input exceeds the configured total-cell limit.")
            }
            row.append(field)
            cells += 1
            field = ""
            fieldScalars = 0
            state = .startField
        }
        func finishRecord() throws {
            try finishField()
            guard rows.count < maximumRecords else {
                throw limit("recordLimitExceeded", "Input exceeds the configured record limit.")
            }
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
                else { try appendFieldScalar(scalar) }
                return
            }
            if state == .afterQuote, scalar == "\"" {
                try appendFieldScalar("\"")
                state = .quoted
                return
            }
            if scalar == delimiter {
                try finishField()
                recordStarted = true
                return
            }
            if scalar == "\r" || scalar == "\n" {
                try finishRecord()
                if scalar == "\r" { pendingCR = true }
                return
            }
            switch state {
            case .startField:
                recordStarted = true
                if scalar == "\"" { state = .quoted }
                else { try appendFieldScalar(scalar); state = .unquoted }
            case .unquoted:
                if scalar == "\"" { throw malformed("A quote appeared inside an unquoted field.") }
                try appendFieldScalar(scalar)
            case .afterQuote:
                throw malformed("Text followed a closing quote.")
            case .quoted:
                break
            }
        }

        var iterator = text.unicodeScalars.makeIterator()
        while true {
            var chunk: [Unicode.Scalar] = []
            let boundedChunkSize = min(chunkSize, 4_096)
            chunk.reserveCapacity(boundedChunkSize)
            for _ in 0..<boundedChunkSize {
                guard let scalar = iterator.next() else { break }
                chunk.append(scalar)
            }
            if chunk.isEmpty { break }
            if Task.isCancelled { throw OutputPublicationError.cancelled }
            for scalar in chunk { try consume(scalar) }
        }
        if state == .quoted { throw malformed("Quoted field was not closed before end of file.") }
        if recordStarted { try finishRecord() }
        return rows
    }
}
