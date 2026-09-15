import Foundation

nonisolated final class BIFF8WorkbookReader {
    private let limits: ResourceLimits
    init(limits: ResourceLimits) { self.limits = limits }

    func read(_ url: URL) throws -> WorkbookDocument {
        let file = try BoundedInputReader.read(url, maximumBytes: limits.documentInputBytes)
        let bytes = try CompoundWorkbookReader(file, maximumStreamBytes: limits.documentInputBytes,
                                               maximumDirectoryEntries: limits.archiveEntries).workbookStream()
        guard bytes.count >= 8 else { throw invalid("XLS Workbook BIFF stream is too short.") }
        let first = try record(bytes, at: 0)
        guard first.id == 0x0809, first.length >= 4, u16(bytes, first.body) == 0x0600,
              u16(bytes, first.body + 2) == 0x0005 else {
            throw InputDiagnostic(code: "biffVariantUnsupported", stage: "parse", summary: "XLS Workbook stream is not BIFF8 globals.")
        }
        var position = first.next
        var boundSheets: [(name: String, offset: Int)] = []
        var strings: [String] = []
        var date1904 = false
        var formatIDs: [Int] = []
        var records = 0
        var globalsEnd: Int?
        while position < bytes.count {
            if Task.isCancelled { throw OutputPublicationError.cancelled }
            let item = try record(bytes, at: position)
            records += 1
            guard records <= limits.valueNodes else {
                throw InputDiagnostic(code: "biffRecordLimitExceeded", stage: "parse", summary: "XLS BIFF record count exceeds the configured limit.")
            }
            if item.id == 0x002F {
                throw InputDiagnostic(code: "encryptedXLSUnsupported", stage: "parse", summary: "Encrypted XLS Workbook requires a password and is not imported.")
            }
            switch item.id {
            case 0x000A:
                globalsEnd = item.next
                position = item.next
                break
            case 0x0085:
                guard item.length >= 8 else { throw invalid("XLS BoundSheet8 record is malformed.") }
                let sheetOffset = Int(u32(bytes, item.body))
                let sheetType = bytes[item.body + 5]
                guard sheetType == 0 else {
                    throw InputDiagnostic(code: "xlsSheetVariantUnsupported", stage: "parse", summary: "XLS contains a chart, macro, or dialog sheet outside the worksheet subset.")
                }
                let nameCount = Int(bytes[item.body + 6])
                let flags = bytes[item.body + 7]
                let name = try shortUnicode(bytes, at: item.body + 8, count: nameCount,
                                            flags: flags, end: item.next)
                boundSheets.append((name, sheetOffset))
            case 0x00FC:
                strings = try sharedStrings(bytes, item: item)
            case 0x0022:
                guard item.length >= 2 else { throw invalid("XLS Date1904 record is malformed.") }
                date1904 = u16(bytes, item.body) == 1
            case 0x00E0:
                guard item.length >= 4 else { throw invalid("XLS XF record is malformed.") }
                formatIDs.append(Int(u16(bytes, item.body + 2)))
            default: break
            }
            if globalsEnd != nil { break }
            position = item.next
        }
        guard let globalsEnd, !boundSheets.isEmpty, boundSheets.count <= limits.spreadsheetSheets else {
            throw InputDiagnostic(code: "invalidXLS", stage: "parse", summary: "XLS globals or worksheet list is missing or exceeds the sheet limit.")
        }
        var seenOffsets = Set<Int>()
        var sheets: [WorkbookSheet] = []
        var warnings: Set<String> = ["biff8Subset"]
        var totalCells = 0
        for (index, bound) in boundSheets.enumerated() {
            guard bound.offset >= globalsEnd, bound.offset < bytes.count,
                  seenOffsets.insert(bound.offset).inserted else {
                throw invalid("XLS BoundSheet8 worksheet pointer is invalid or duplicated.")
            }
            sheets.append(try worksheet(bytes, at: bound.offset, name: bound.name, index: index + 1,
                                        strings: strings, formats: formatIDs, date1904: date1904,
                                        totalCells: &totalCells, warnings: &warnings))
        }
        return WorkbookDocument(version: "2.0", sourceFormat: "xls-biff8", fileName: url.lastPathComponent,
                                sheets: sheets, warnings: warnings.sorted())
    }

    private struct Record { let id: UInt16; let body: Int; let length: Int; let next: Int }
    private func record(_ bytes: Data, at position: Int) throws -> Record {
        guard position <= bytes.count - 4 else { throw invalid("XLS BIFF record header is truncated.") }
        let length = Int(u16(bytes, position + 2))
        guard length <= 8_224, length <= bytes.count - position - 4 else {
            throw invalid("XLS BIFF record length is out of bounds.")
        }
        return Record(id: u16(bytes, position), body: position + 4, length: length,
                      next: position + 4 + length)
    }

    private func worksheet(_ bytes: Data, at start: Int, name: String, index: Int, strings: [String],
                           formats: [Int], date1904: Bool, totalCells: inout Int,
                           warnings: inout Set<String>) throws -> WorkbookSheet {
        let bof = try record(bytes, at: start)
        guard bof.id == 0x0809, bof.length >= 4, u16(bytes, bof.body) == 0x0600,
              u16(bytes, bof.body + 2) == 0x0010 else {
            throw InputDiagnostic(code: "biffVariantUnsupported", stage: "parse", summary: "XLS worksheet is not a BIFF8 worksheet substream.")
        }
        var position = bof.next
        var cells: [WorkbookCell] = []
        var merges: [String] = []
        var seen = Set<String>()
        var recordCount = 0
        var ended = false

        func add(_ cell: WorkbookCell) throws {
            _ = try SpreadsheetCoordinate.parse(cell.coordinate, maximumRows: limits.spreadsheetRows,
                                                 maximumColumns: limits.spreadsheetColumns)
            guard seen.insert(cell.coordinate).inserted else {
                throw InputDiagnostic(code: "duplicateCellCoordinate", stage: "parse", summary: "XLS worksheet cell coordinates collide.")
            }
            guard totalCells < limits.spreadsheetCells else {
                throw InputDiagnostic(code: "spreadsheetCellLimitExceeded", stage: "parse", summary: "XLS worksheet exceeds the total-cell limit.")
            }
            totalCells += 1
            cells.append(cell)
        }
        while position < bytes.count {
            if Task.isCancelled { throw OutputPublicationError.cancelled }
            let item = try record(bytes, at: position)
            recordCount += 1
            guard recordCount <= limits.valueNodes else {
                throw InputDiagnostic(code: "biffRecordLimitExceeded", stage: "parse", summary: "XLS worksheet has too many BIFF records.")
            }
            if item.id == 0x002F {
                throw InputDiagnostic(code: "encryptedXLSUnsupported", stage: "parse", summary: "Encrypted XLS worksheet is not imported.")
            }
            if item.id == 0x000A { ended = true; break }
            switch item.id {
            case 0x00FD:
                guard item.length == 10 else { throw invalid("XLS LabelSst record is malformed.") }
                let coord = try coordinate(bytes, body: item.body)
                let id = Int(u32(bytes, item.body + 6))
                guard id >= 0, id < strings.count else {
                    throw InputDiagnostic(code: "invalidSharedStringIndex", stage: "parse", summary: "XLS shared string index is invalid.")
                }
                try add(cell(coord, type: "string", text: strings[id], style: Int(u16(bytes, item.body + 4))))
            case 0x0203:
                guard item.length == 14 else { throw invalid("XLS Number record is malformed.") }
                let coord = try coordinate(bytes, body: item.body)
                let style = Int(u16(bytes, item.body + 4))
                let numeric = Double(bitPattern: u64(bytes, item.body + 6))
                guard numeric.isFinite else { throw invalid("XLS numeric cell is not finite.") }
                try add(numberCell(coord, numeric: numeric, style: style, formats: formats,
                                   date1904: date1904))
            case 0x027E:
                guard item.length == 10 else { throw invalid("XLS RK record is malformed.") }
                let coord = try coordinate(bytes, body: item.body)
                let style = Int(u16(bytes, item.body + 4))
                try add(numberCell(coord, numeric: try rk(u32(bytes, item.body + 6)), style: style,
                                   formats: formats, date1904: date1904))
            case 0x00BD:
                guard item.length >= 12, (item.length - 6).isMultiple(of: 6) else {
                    throw invalid("XLS MulRK record is malformed.")
                }
                let row = Int(u16(bytes, item.body)) + 1
                let firstColumn = Int(u16(bytes, item.body + 2)) + 1
                let count = (item.length - 6) / 6
                let lastColumn = Int(u16(bytes, item.next - 2)) + 1
                guard firstColumn + count - 1 == lastColumn else { throw invalid("XLS MulRK column bounds disagree.") }
                for offset in 0..<count {
                    let body = item.body + 4 + offset * 6
                    let coord = SpreadsheetCoordinate.make(row: row, column: firstColumn + offset)
                    let style = Int(u16(bytes, body))
                    try add(numberCell(coord, numeric: try rk(u32(bytes, body + 2)), style: style,
                                       formats: formats, date1904: date1904))
                }
            case 0x0205:
                guard item.length == 8 else { throw invalid("XLS BoolErr record is malformed.") }
                let coord = try coordinate(bytes, body: item.body)
                let value = bytes[item.body + 6]
                let isError = bytes[item.body + 7] == 1
                let text = isError ? errorText(value) : (value == 1 ? "true" : "false")
                try add(cell(coord, type: isError ? "error" : "boolean", text: text,
                             style: Int(u16(bytes, item.body + 4))))
            case 0x0201:
                guard item.length == 6 else { throw invalid("XLS Blank record is malformed.") }
                let coord = try coordinate(bytes, body: item.body)
                try add(cell(coord, type: "blank", style: Int(u16(bytes, item.body + 4))))
            case 0x0006:
                guard item.length >= 22 else { throw invalid("XLS Formula record is malformed.") }
                let coord = try coordinate(bytes, body: item.body)
                let style = Int(u16(bytes, item.body + 4))
                let tokenCount = Int(u16(bytes, item.body + 20))
                guard tokenCount > 0, tokenCount <= item.length - 22 else {
                    throw invalid("XLS Formula token length is out of bounds.")
                }
                let (expression, supported) = formula(bytes[item.body + 22..<(item.body + 22 + tokenCount)],
                                                      at: coord)
                if !supported { warnings.insert("formulaTokenVariantUnsupported") }
                warnings.insert("formulaCacheUnverified")
                let cached = Double(bitPattern: u64(bytes, item.body + 6))
                let cachedText = cached.isFinite ? numericText(cached) : nil
                try add(WorkbookCell(coordinate: coord, type: "number", text: nil,
                                     numericLexeme: nil, formula: expression, cachedValue: cachedText,
                                     cacheStatus: cachedText == nil ? "unknown" : "unverified",
                                     dateValue: nil, dateEpoch: nil, timezone: nil, styleIndex: style))
            case 0x00E5:
                guard item.length >= 2 else { throw invalid("XLS MergeCells record is malformed.") }
                let count = Int(u16(bytes, item.body))
                guard count <= 1_026, item.length == 2 + count * 8 else {
                    throw invalid("XLS MergeCells count or length is malformed.")
                }
                for number in 0..<count {
                    let offset = item.body + 2 + number * 8
                    let first = SpreadsheetCoordinate.make(row: Int(u16(bytes, offset)) + 1,
                                                           column: Int(u16(bytes, offset + 4)) + 1)
                    let last = SpreadsheetCoordinate.make(row: Int(u16(bytes, offset + 2)) + 1,
                                                          column: Int(u16(bytes, offset + 6)) + 1)
                    _ = try SpreadsheetCoordinate.parse(first, maximumRows: limits.spreadsheetRows,
                                                         maximumColumns: limits.spreadsheetColumns)
                    _ = try SpreadsheetCoordinate.parse(last, maximumRows: limits.spreadsheetRows,
                                                        maximumColumns: limits.spreadsheetColumns)
                    merges.append(first + ":" + last)
                }
            case 0x0204, 0x00D6, 0x00BE, 0x0007:
                throw InputDiagnostic(code: "biffCellVariantUnsupported", stage: "parse",
                                      summary: "XLS worksheet contains a cell record outside the BIFF8 subset.")
            default: break
            }
            position = item.next
        }
        guard ended else { throw invalid("XLS worksheet has no BIFF EOF record.") }
        return WorkbookSheet(index: index, name: name, cells: cells, mergedRanges: merges)
    }

    private func sharedStrings(_ bytes: Data, item: Record) throws -> [String] {
        guard item.length >= 8 else { throw invalid("XLS SST record is malformed.") }
        let unique = Int(u32(bytes, item.body + 4))
        guard unique >= 0, unique <= limits.valueNodes else {
            throw InputDiagnostic(code: "nodeLimitExceeded", stage: "parse", summary: "XLS shared string count exceeds the limit.")
        }
        var strings: [String] = []
        var cursor = item.body + 8
        for _ in 0..<unique {
            guard cursor + 3 <= item.next else {
                throw InputDiagnostic(code: "biffSSTContinueUnsupported", stage: "parse", summary: "XLS split shared strings are outside this BIFF8 subset.")
            }
            let count = Int(u16(bytes, cursor))
            let flags = bytes[cursor + 2]
            guard flags & 0x0C == 0 else {
                throw InputDiagnostic(code: "biffRichStringUnsupported", stage: "parse", summary: "XLS rich or extended shared strings are outside this subset.")
            }
            cursor += 3
            let length = count * (flags & 1 == 1 ? 2 : 1)
            guard length <= item.next - cursor else {
                throw InputDiagnostic(code: "biffSSTContinueUnsupported", stage: "parse", summary: "XLS split shared strings are outside this BIFF8 subset.")
            }
            let text = try unicode(bytes, at: cursor, count: count, flags: flags, end: item.next)
            strings.append(text)
            cursor += length
        }
        return strings
    }

    private func shortUnicode(_ bytes: Data, at start: Int, count: Int, flags: UInt8, end: Int) throws -> String {
        guard count > 0, count <= 31 else { throw invalid("XLS sheet name length is invalid.") }
        return try unicode(bytes, at: start, count: count, flags: flags, end: end)
    }

    private func unicode(_ bytes: Data, at start: Int, count: Int, flags: UInt8, end: Int) throws -> String {
        let length = count * (flags & 1 == 1 ? 2 : 1)
        guard flags & ~UInt8(1) == 0, length <= end - start else {
            throw InputDiagnostic(code: "biffStringVariantUnsupported", stage: "parse", summary: "XLS string encoding or length is unsupported.")
        }
        let slice = bytes[start..<(start + length)]
        guard let text = String(data: slice, encoding: flags & 1 == 1 ? .utf16LittleEndian : .isoLatin1) else {
            throw invalid("XLS string bytes are malformed.")
        }
        return text
    }

    private func coordinate(_ bytes: Data, body: Int) throws -> String {
        let coord = SpreadsheetCoordinate.make(row: Int(u16(bytes, body)) + 1,
                                                column: Int(u16(bytes, body + 2)) + 1)
        _ = try SpreadsheetCoordinate.parse(coord, maximumRows: limits.spreadsheetRows,
                                             maximumColumns: limits.spreadsheetColumns)
        return coord
    }

    private func cell(_ coord: String, type: String, text: String? = nil, style: Int? = nil) -> WorkbookCell {
        WorkbookCell(coordinate: coord, type: type, text: text, numericLexeme: nil, formula: nil,
                     cachedValue: nil, cacheStatus: nil, dateValue: nil, dateEpoch: nil,
                     timezone: nil, styleIndex: style)
    }

    private func numberCell(_ coord: String, numeric: Double, style: Int, formats: [Int],
                            date1904: Bool) -> WorkbookCell {
        let lexeme = numericText(numeric)
        let format = style < formats.count ? formats[style] : 0
        let dateFormat = [14, 15, 16, 17, 18, 19, 20, 21, 22, 45, 46, 47].contains(format)
        return WorkbookCell(coordinate: coord, type: dateFormat ? "date" : "number", text: nil,
                            numericLexeme: lexeme, formula: nil, cachedValue: nil, cacheStatus: nil,
                            dateValue: dateFormat ? SpreadsheetDate.excelSerial(lexeme, epoch1904: date1904) : nil,
                            dateEpoch: dateFormat ? (date1904 ? "1904" : "1900") : nil,
                            timezone: dateFormat ? "floating" : nil, styleIndex: style)
    }

    private func rk(_ raw: UInt32) throws -> Double {
        let number: Double
        if raw & 0x2 != 0 { number = Double(Int32(bitPattern: raw) >> 2) }
        else { number = Double(bitPattern: UInt64(raw & 0xFFFFFFFC) << 32) }
        let scaled = raw & 0x1 != 0 ? number / 100 : number
        guard scaled.isFinite else { throw invalid("XLS RK number is not finite.") }
        return scaled
    }

    private func formula(_ tokens: Data, at coordinate: String) -> (String, Bool) {
        let parsed = try? SpreadsheetCoordinate.parse(coordinate, maximumRows: limits.spreadsheetRows,
                                                      maximumColumns: limits.spreadsheetColumns)
        var stack: [String] = []
        var cursor = tokens.startIndex
        while cursor < tokens.endIndex {
            let token = tokens[cursor]
            cursor += 1
            switch token {
            case 0x1E:
                guard cursor + 2 <= tokens.endIndex else { return tokenHex(tokens) }
                stack.append(String(u16(tokens, cursor)))
                cursor += 2
            case 0x1F:
                guard cursor + 8 <= tokens.endIndex else { return tokenHex(tokens) }
                stack.append(numericText(Double(bitPattern: u64(tokens, cursor))))
                cursor += 8
            case 0x24, 0x44, 0x64:
                guard cursor + 4 <= tokens.endIndex, let parsed else { return tokenHex(tokens) }
                let rawRow = u16(tokens, cursor)
                let rawColumn = u16(tokens, cursor + 2)
                cursor += 4
                let rowRelative = rawColumn & 0x8000 != 0
                let columnRelative = rawColumn & 0x4000 != 0
                let row = rowRelative ? parsed.row + Int(Int16(bitPattern: rawRow)) : Int(rawRow) + 1
                let rawCol = Int(rawColumn & 0x3FFF)
                let colOffset = rawCol & 0x2000 != 0 ? rawCol - 0x4000 : rawCol
                let column = columnRelative ? parsed.column + colOffset : rawCol + 1
                guard row > 0, column > 0, row <= limits.spreadsheetRows,
                      column <= limits.spreadsheetColumns else { return tokenHex(tokens) }
                stack.append(SpreadsheetCoordinate.make(row: row, column: column))
            case 0x03, 0x04, 0x05, 0x06:
                guard stack.count >= 2 else { return tokenHex(tokens) }
                let right = stack.removeLast()
                let left = stack.removeLast()
                let operatorText: String = token == 0x03 ? "+" : token == 0x04 ? "-" : token == 0x05 ? "*" : "/"
                stack.append(left + operatorText + right)
            default: return tokenHex(tokens)
            }
        }
        return stack.count == 1 ? (stack[0], true) : tokenHex(tokens)
    }

    private func tokenHex(_ tokens: Data) -> (String, Bool) {
        ("BIFF8 tokens " + tokens.map { String(format: "%02X", $0) }.joined(), false)
    }

    private func errorText(_ code: UInt8) -> String {
        switch code {
        case 0: return "#NULL!"
        case 7: return "#DIV/0!"
        case 15: return "#VALUE!"
        case 23: return "#REF!"
        case 29: return "#NAME?"
        case 36: return "#NUM!"
        case 42: return "#N/A"
        default: return "#ERROR(\(code))"
        }
    }

    private func numericText(_ value: Double) -> String { String(format: "%.17g", value) }
    private func invalid(_ summary: String) -> InputDiagnostic {
        InputDiagnostic(code: "invalidXLS", stage: "parse", summary: summary)
    }
    private func u16(_ bytes: Data, _ position: Int) -> UInt16 {
        UInt16(bytes[position]) | UInt16(bytes[position + 1]) << 8
    }
    private func u32(_ bytes: Data, _ position: Int) -> UInt32 {
        UInt32(u16(bytes, position)) | UInt32(u16(bytes, position + 2)) << 16
    }
    private func u64(_ bytes: Data, _ position: Int) -> UInt64 {
        UInt64(u32(bytes, position)) | UInt64(u32(bytes, position + 4)) << 32
    }
}
