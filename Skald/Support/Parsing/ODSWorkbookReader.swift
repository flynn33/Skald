import Foundation

nonisolated final class ODSWorkbookReader {
    private let limits: ResourceLimits
    init(limits: ResourceLimits) { self.limits = limits }

    func read(_ url: URL) throws -> WorkbookDocument {
        let data = try BoundedInputReader.read(url, maximumBytes: limits.documentInputBytes)
        let archive = try SafeZipArchive(data: data, maximumEntries: limits.archiveEntries,
                                         maximumExpandedBytes: limits.archiveExpandedBytes,
                                         maximumMemberBytes: limits.documentInputBytes)
        let parts = Dictionary(uniqueKeysWithValues: archive.entries.filter { !$0.isDirectory }.map { ($0.path, $0) })
        guard let mimetypeEntry = parts["mimetype"],
              String(data: try archive.extract(mimetypeEntry), encoding: .utf8) == "application/vnd.oasis.opendocument.spreadsheet" else {
            throw InputDiagnostic(code: "invalidODS", stage: "package", summary: "ODS spreadsheet MIME member is missing or invalid.")
        }
        let manifest = try xmlPart("META-INF/manifest.xml", archive: archive, parts: parts)
        guard manifest.name == "manifest", manifest.descendants("file-entry").contains(where: { $0.attribute("full-path") == "content.xml" }) else {
            throw InputDiagnostic(code: "invalidODS", stage: "package", summary: "ODS package manifest does not list content.xml.")
        }
        guard manifest.descendants("encryption-data").isEmpty else {
            throw InputDiagnostic(code: "encryptedODSUnsupported", stage: "package", summary: "Encrypted ODS packages require a password and are not imported.")
        }
        let content = try xmlPart("content.xml", archive: archive, parts: parts)
        guard content.name == "document-content", let spreadsheet = content.descendants("spreadsheet").first else {
            throw InputDiagnostic(code: "invalidODS", stage: "parse", summary: "ODS spreadsheet body is missing.")
        }
        let epoch = spreadsheet.descendants("null-date").first?.attribute("date-value") ?? "1899-12-30"
        let tables = spreadsheet.children("table")
        guard !tables.isEmpty, tables.count <= limits.spreadsheetSheets else {
            throw InputDiagnostic(code: "spreadsheetSheetLimitExceeded", stage: "parse", summary: "ODS has no sheets or exceeds the sheet limit.")
        }
        var parsed: [WorkbookSheet] = []
        var totalCells = 0
        var warnings = Set<String>()
        for (ordinal, table) in tables.enumerated() {
            if Task.isCancelled { throw OutputPublicationError.cancelled }
            guard let name = table.attribute("name") else {
                throw InputDiagnostic(code: "invalidODS", stage: "parse", summary: "ODS sheet name is missing.")
            }
            parsed.append(try parseTable(table, name: name, index: ordinal + 1, epoch: epoch,
                                         totalCells: &totalCells, warnings: &warnings))
        }
        return WorkbookDocument(version: "2.0", sourceFormat: "ods", fileName: url.lastPathComponent,
                                sheets: parsed, warnings: warnings.sorted())
    }

    private func xmlPart(_ path: String, archive: SafeZipArchive, parts: [String: SafeZipEntry]) throws -> ContainerXMLNode {
        guard let entry = parts[path] else {
            throw InputDiagnostic(code: "invalidODS", stage: "package", summary: "Required ODS package part is missing.")
        }
        return try ContainerXML.parse(archive.extract(entry), maximumBytes: limits.structuredInputBytes,
                                      maximumNodes: limits.valueNodes, maximumDepth: limits.nestingDepth)
    }

    private func parseTable(_ table: ContainerXMLNode, name: String, index: Int, epoch: String,
                            totalCells: inout Int, warnings: inout Set<String>) throws -> WorkbookSheet {
        var cells: [WorkbookCell] = []
        var merges: [String] = []
        var rowNumber = 0
        for row in table.descendants("table-row") {
            let rowRepeat = try repeatCount(row.attribute("number-rows-repeated"))
            guard rowRepeat <= limits.spreadsheetRows - rowNumber else {
                throw InputDiagnostic(code: "spreadsheetRowLimitExceeded", stage: "parse", summary: "ODS repeated rows exceed the configured limit.")
            }
            for _ in 0..<rowRepeat {
                if Task.isCancelled { throw OutputPublicationError.cancelled }
                rowNumber += 1
                var columnNumber = 0
                for content in row.contents {
                    guard case .element(let element) = content,
                          element.name == "table-cell" || element.name == "covered-table-cell" else { continue }
                    let columnRepeat = try repeatCount(element.attribute("number-columns-repeated"))
                    guard columnRepeat <= limits.spreadsheetColumns - columnNumber else {
                        throw InputDiagnostic(code: "spreadsheetColumnLimitExceeded", stage: "parse", summary: "ODS repeated columns exceed the configured limit.")
                    }
                    let hasContent = element.attribute("formula") != nil || element.attribute("value") != nil ||
                        element.attribute("date-value") != nil || element.attribute("boolean-value") != nil ||
                        element.attribute("string-value") != nil || !element.descendants("p").isEmpty
                    let hasSpan = element.attribute("number-columns-spanned").map { $0 != "1" } ?? false ||
                        (element.attribute("number-rows-spanned").map { $0 != "1" } ?? false)
                    if element.name == "covered-table-cell" || (!hasContent && !hasSpan) {
                        columnNumber += columnRepeat
                        continue
                    }
                    for _ in 0..<columnRepeat {
                        columnNumber += 1
                        let coordinate = SpreadsheetCoordinate.make(row: rowNumber, column: columnNumber)
                        let formula = element.attribute("formula")
                        let valueType = element.attribute("value-type") ?? ""
                        let paragraphs = element.descendants("p").map(\.text)
                        let visibleText = paragraphs.isEmpty ? nil : paragraphs.joined(separator: "\n")
                        let rawNumeric = element.attribute("value")
                        let rawDate = element.attribute("date-value")
                        let rawBool = element.attribute("boolean-value")
                        let rawString = element.attribute("string-value")
                        let meaningful = formula != nil || visibleText != nil || rawNumeric != nil || rawDate != nil || rawBool != nil || rawString != nil
                        if meaningful {
                            guard totalCells < limits.spreadsheetCells else {
                                throw InputDiagnostic(code: "spreadsheetCellLimitExceeded", stage: "parse", summary: "ODS exceeds the total-cell limit.")
                            }
                            totalCells += 1
                            if formula != nil { warnings.insert("formulaCacheUnverified") }
                            let type: String
                            let text: String?
                            let lexeme: String?
                            let date: String?
                            switch valueType {
                            case "string", "":
                                type = "string"; text = rawString ?? visibleText; lexeme = nil; date = nil
                            case "float", "percentage", "currency":
                                guard let rawNumeric, Decimal(string: rawNumeric, locale: Locale(identifier: "en_US_POSIX")) != nil else {
                                    throw InputDiagnostic(code: "invalidNumericCell", stage: "parse", summary: "ODS numeric cell is malformed.")
                                }
                                type = "number"; text = visibleText; lexeme = rawNumeric; date = nil
                            case "boolean":
                                guard rawBool == "true" || rawBool == "false" else {
                                    throw InputDiagnostic(code: "invalidBooleanCell", stage: "parse", summary: "ODS boolean cell is malformed.")
                                }
                                type = "boolean"; text = rawBool; lexeme = nil; date = nil
                            case "date", "time":
                                guard let rawDate else {
                                    throw InputDiagnostic(code: "invalidDateCell", stage: "parse", summary: "ODS date cell lacks a value.")
                                }
                                type = "date"; text = visibleText; lexeme = nil; date = rawDate
                            case "error":
                                type = "error"; text = visibleText; lexeme = nil; date = nil
                            default:
                                throw InputDiagnostic(code: "odsCellVariantUnsupported", stage: "parse", summary: "ODS cell type is unsupported.")
                            }
                            let cached = formula == nil ? nil : (rawNumeric ?? rawDate ?? rawBool ?? rawString ?? visibleText)
                            cells.append(WorkbookCell(coordinate: coordinate, type: type, text: text,
                                                      numericLexeme: lexeme, formula: formula, cachedValue: cached,
                                                      cacheStatus: formula == nil ? nil : (cached == nil ? "unknown" : "unverified"),
                                                      dateValue: date, dateEpoch: type == "date" ? epoch : nil,
                                                      timezone: type == "date" ? "floating" : nil, styleIndex: nil))
                        }
                        let columnsSpanned = try repeatCount(element.attribute("number-columns-spanned"))
                        let rowsSpanned = try repeatCount(element.attribute("number-rows-spanned"))
                        if columnsSpanned > 1 || rowsSpanned > 1 {
                            guard columnNumber + columnsSpanned - 1 <= limits.spreadsheetColumns,
                                  rowNumber + rowsSpanned - 1 <= limits.spreadsheetRows else {
                                throw InputDiagnostic(code: "invalidMergedRange", stage: "parse", summary: "ODS merged cell exceeds sheet limits.")
                            }
                            merges.append(coordinate + ":" + SpreadsheetCoordinate.make(row: rowNumber + rowsSpanned - 1,
                                                                                           column: columnNumber + columnsSpanned - 1))
                        }
                    }
                }
            }
        }
        return WorkbookSheet(index: index, name: name, cells: cells, mergedRanges: merges)
    }

    private func repeatCount(_ value: String?) throws -> Int {
        guard let value else { return 1 }
        guard let count = Int(value), count > 0 else {
            throw InputDiagnostic(code: "invalidRepeatCount", stage: "parse", summary: "ODS repeated row or column count is invalid.")
        }
        return count
    }
}
