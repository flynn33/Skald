import Foundation

nonisolated final class XLSXWorkbookReader {
    private let limits: ResourceLimits
    init(limits: ResourceLimits) { self.limits = limits }

    func read(_ url: URL) throws -> WorkbookDocument {
        let data = try BoundedInputReader.read(url, maximumBytes: limits.documentInputBytes)
        let archive = try SafeZipArchive(data: data, maximumEntries: limits.archiveEntries,
                                         maximumExpandedBytes: limits.archiveExpandedBytes,
                                         maximumMemberBytes: limits.documentInputBytes)
        let parts = Dictionary(uniqueKeysWithValues: archive.entries.filter { !$0.isDirectory }.map { ($0.path, $0) })
        _ = try xmlPart("[Content_Types].xml", archive: archive, parts: parts)
        let rootRelationships = try xmlPart("_rels/.rels", archive: archive, parts: parts)
        let rootLinks = try relationships(rootRelationships, base: "")
        guard let workbookPath = rootLinks.values.first(where: { $0.type.hasSuffix("/officeDocument") })?.path else {
            throw InputDiagnostic(code: "invalidXLSX", stage: "package", summary: "Workbook relationship is missing.")
        }
        guard workbookPath.hasPrefix("xl/") else {
            throw InputDiagnostic(code: "invalidXLSX", stage: "package", summary: "Workbook part is outside the expected SpreadsheetML location.")
        }
        let workbook = try xmlPart(workbookPath, archive: archive, parts: parts)
        guard workbook.name == "workbook", workbook.namespace?.contains("spreadsheetml") == true else {
            throw InputDiagnostic(code: "xlsxVariantUnsupported", stage: "parse", summary: "Workbook XML namespace is outside the supported SpreadsheetML subset.")
        }
        let workbookDirectory = String(workbookPath.prefix(through: workbookPath.lastIndex(of: "/")!))
        let workbookRelsPath = workbookDirectory + "_rels/" + URL(fileURLWithPath: workbookPath).lastPathComponent + ".rels"
        let workbookRels = try xmlPart(workbookRelsPath, archive: archive, parts: parts)
        let links = try relationships(workbookRels, base: workbookDirectory)
        let date1904 = workbook.first("workbookPr")?.attribute("date1904") == "1"
        let sharedPath = links.values.first(where: { $0.type.hasSuffix("/sharedStrings") })?.path
        let strings = try sharedPath.map { try sharedStrings(xmlPart($0, archive: archive, parts: parts)) } ?? []
        let stylesPath = links.values.first(where: { $0.type.hasSuffix("/styles") })?.path
        let dateStyles = try stylesPath.map { try dateStyleIndices(xmlPart($0, archive: archive, parts: parts)) } ?? []
        guard let sheetList = workbook.first("sheets") else {
            throw InputDiagnostic(code: "invalidXLSX", stage: "parse", summary: "Workbook sheet list is missing.")
        }
        let sheets = sheetList.children("sheet")
        guard !sheets.isEmpty, sheets.count <= limits.spreadsheetSheets else {
            throw InputDiagnostic(code: "spreadsheetSheetLimitExceeded", stage: "parse", summary: "Workbook has no sheets or exceeds the sheet limit.")
        }
        var parsed: [WorkbookSheet] = []
        var warnings = Set<String>()
        var totalCells = 0
        for (ordinal, sheet) in sheets.enumerated() {
            if Task.isCancelled { throw OutputPublicationError.cancelled }
            guard let name = sheet.attribute("name"), let id = sheet.attribute("id"),
                  let link = links[id], link.type.hasSuffix("/worksheet") else {
                throw InputDiagnostic(code: "invalidXLSX", stage: "relationships", summary: "Worksheet name or relationship is missing.")
            }
            let worksheet = try xmlPart(link.path, archive: archive, parts: parts)
            guard worksheet.name == "worksheet", worksheet.namespace == workbook.namespace else {
                throw InputDiagnostic(code: "xlsxVariantUnsupported", stage: "parse", summary: "Worksheet namespace is unsupported.")
            }
            let content = try parseSheet(worksheet, name: name, index: ordinal + 1, shared: strings,
                                         dateStyles: dateStyles, date1904: date1904,
                                         totalCells: &totalCells, warnings: &warnings)
            parsed.append(content)
        }
        return WorkbookDocument(version: "2.0", sourceFormat: "xlsx", fileName: url.lastPathComponent,
                                sheets: parsed, warnings: warnings.sorted())
    }

    private func xmlPart(_ path: String, archive: SafeZipArchive, parts: [String: SafeZipEntry]) throws -> ContainerXMLNode {
        guard let entry = parts[path] else {
            throw InputDiagnostic(code: "invalidXLSX", stage: "package", summary: "Required SpreadsheetML package part is missing.")
        }
        return try ContainerXML.parse(archive.extract(entry), maximumBytes: limits.structuredInputBytes,
                                      maximumNodes: limits.valueNodes, maximumDepth: limits.nestingDepth)
    }

    private struct Link { let type: String; let path: String }
    private func relationships(_ root: ContainerXMLNode, base: String) throws -> [String: Link] {
        guard root.name == "Relationships" else {
            throw InputDiagnostic(code: "invalidXLSX", stage: "relationships", summary: "Package relationship part is malformed.")
        }
        var links: [String: Link] = [:]
        for relation in root.children("Relationship") {
            guard let id = relation.attribute("Id"), let type = relation.attribute("Type"),
                  let target = relation.attribute("Target") else {
                throw InputDiagnostic(code: "invalidXLSX", stage: "relationships", summary: "Package relationship lacks required fields.")
            }
            guard relation.attribute("TargetMode") != "External", !type.lowercased().contains("externallink") else {
                throw InputDiagnostic(code: "externalLinkDenied", stage: "relationships", summary: "External workbook relationships are denied.")
            }
            let path = try resolve(target, base: base)
            guard links[id] == nil else {
                throw InputDiagnostic(code: "relationshipCollision", stage: "relationships", summary: "Workbook relationship IDs collide.")
            }
            links[id] = Link(type: type, path: path)
        }
        return links
    }

    private func resolve(_ target: String, base: String) throws -> String {
        guard !target.isEmpty, !target.contains("\\"), !target.contains(":") else {
            throw InputDiagnostic(code: "relationshipPathDenied", stage: "relationships", summary: "Workbook relationship target is unsafe.")
        }
        var segments = target.hasPrefix("/") ? [] : base.split(separator: "/").map(String.init)
        for part in target.split(separator: "/") {
            if part == "." { continue }
            if part == ".." {
                guard !segments.isEmpty else {
                    throw InputDiagnostic(code: "relationshipPathDenied", stage: "relationships", summary: "Workbook relationship escapes the package.")
                }
                segments.removeLast()
            } else { segments.append(String(part)) }
        }
        guard !segments.isEmpty else {
            throw InputDiagnostic(code: "relationshipPathDenied", stage: "relationships", summary: "Workbook relationship has an empty target.")
        }
        return segments.joined(separator: "/")
    }

    private func sharedStrings(_ root: ContainerXMLNode) throws -> [String] {
        guard root.name == "sst" else { throw InputDiagnostic(code: "invalidXLSX", stage: "parse", summary: "Shared string part is malformed.") }
        let items = root.children("si")
        guard items.count <= limits.valueNodes else {
            throw InputDiagnostic(code: "nodeLimitExceeded", stage: "parse", summary: "Shared string count exceeds the configured limit.")
        }
        return items.map { item in item.descendants("t").map(\.text).joined() }
    }

    private func dateStyleIndices(_ root: ContainerXMLNode) throws -> Set<Int> {
        guard root.name == "styleSheet" else { throw InputDiagnostic(code: "invalidXLSX", stage: "parse", summary: "Style part is malformed.") }
        var dateFormats = Set([14, 15, 16, 17, 18, 19, 20, 21, 22, 45, 46, 47])
        for format in root.first("numFmts")?.children("numFmt") ?? [] {
            guard let idText = format.attribute("numFmtId"), let id = Int(idText),
                  let code = format.attribute("formatCode") else { continue }
            let lower = code.lowercased()
            if lower.contains("yy") || lower.contains("dd") || lower.contains("hh") {
                dateFormats.insert(id)
            }
        }
        var indices = Set<Int>()
        for (index, format) in (root.first("cellXfs")?.children("xf") ?? []).enumerated() {
            if let id = Int(format.attribute("numFmtId") ?? ""), dateFormats.contains(id) { indices.insert(index) }
        }
        return indices
    }

    private func parseSheet(_ root: ContainerXMLNode, name: String, index: Int, shared: [String],
                            dateStyles: Set<Int>, date1904: Bool, totalCells: inout Int,
                            warnings: inout Set<String>) throws -> WorkbookSheet {
        var cells: [WorkbookCell] = []
        var seen = Set<String>()
        for row in root.first("sheetData")?.children("row") ?? [] {
            for element in row.children("c") {
                if Task.isCancelled { throw OutputPublicationError.cancelled }
                guard let coordinate = element.attribute("r") else {
                    throw InputDiagnostic(code: "invalidCellCoordinate", stage: "parse", summary: "Worksheet cell has no coordinate.")
                }
                _ = try SpreadsheetCoordinate.parse(coordinate, maximumRows: limits.spreadsheetRows,
                                                     maximumColumns: limits.spreadsheetColumns)
                guard seen.insert(coordinate).inserted else {
                    throw InputDiagnostic(code: "duplicateCellCoordinate", stage: "parse", summary: "Worksheet cell coordinates collide.")
                }
                guard totalCells < limits.spreadsheetCells else {
                    throw InputDiagnostic(code: "spreadsheetCellLimitExceeded", stage: "parse", summary: "Worksheet exceeds the configured total-cell limit.")
                }
                totalCells += 1
                let sourceType = element.attribute("t") ?? "n"
                let style = Int(element.attribute("s") ?? "")
                let formulaNode = element.first("f")
                let formula = formulaNode?.text
                if formulaNode?.attribute("t") == "shared", formula?.isEmpty == true {
                    warnings.insert("sharedFormulaExpressionUnresolved")
                }
                let value = element.first("v")?.text
                let inline = element.first("is")?.descendants("t").map(\.text).joined()
                let hasFormula = formulaNode != nil
                if hasFormula { warnings.insert("formulaCacheUnverified") }
                let dateStyle = style.map { dateStyles.contains($0) } ?? false
                let type: String
                let text: String?
                let lexeme: String?
                let date: String?
                switch sourceType {
                case "s":
                    guard let value, let id = Int(value), id >= 0, id < shared.count else {
                        throw InputDiagnostic(code: "invalidSharedStringIndex", stage: "parse", summary: "Worksheet shared string index is invalid.")
                    }
                    type = "string"; text = shared[id]; lexeme = nil; date = nil
                case "inlineStr":
                    type = "string"; text = inline ?? ""; lexeme = nil; date = nil
                case "str":
                    type = "string"; text = value; lexeme = nil; date = nil
                case "b":
                    guard value == "0" || value == "1" else {
                        throw InputDiagnostic(code: "invalidBooleanCell", stage: "parse", summary: "Worksheet boolean cell is malformed.")
                    }
                    type = "boolean"; text = value == "1" ? "true" : "false"; lexeme = nil; date = nil
                case "e":
                    type = "error"; text = value; lexeme = nil; date = nil
                case "d":
                    type = "date"; text = nil; lexeme = nil; date = value
                case "n", "":
                    if let value, !value.isEmpty {
                        guard Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) != nil else {
                            throw InputDiagnostic(code: "invalidNumericCell", stage: "parse", summary: "Worksheet numeric cell is malformed.")
                        }
                    }
                    type = value == nil ? "blank" : (dateStyle ? "date" : "number")
                    text = nil; lexeme = value
                    date = dateStyle ? value.flatMap { SpreadsheetDate.excelSerial($0, epoch1904: date1904) } : nil
                default:
                    throw InputDiagnostic(code: "xlsxCellVariantUnsupported", stage: "parse", summary: "Worksheet cell type is unsupported.")
                }
                cells.append(WorkbookCell(coordinate: coordinate, type: type, text: text, numericLexeme: lexeme,
                                          formula: formula, cachedValue: hasFormula ? value : nil,
                                          cacheStatus: hasFormula ? (value == nil ? "unknown" : "unverified") : nil,
                                          dateValue: date, dateEpoch: type == "date" ? (date1904 ? "1904" : "1900") : nil,
                                          timezone: type == "date" ? "floating" : nil, styleIndex: style))
            }
        }
        let merges = root.first("mergeCells")?.children("mergeCell").compactMap { $0.attribute("ref") } ?? []
        for range in merges {
            let coordinates = range.split(separator: ":").map(String.init)
            guard coordinates.count == 2 else {
                throw InputDiagnostic(code: "invalidMergedRange", stage: "parse", summary: "Worksheet merged range is malformed.")
            }
            for coordinate in coordinates {
                _ = try SpreadsheetCoordinate.parse(coordinate, maximumRows: limits.spreadsheetRows,
                                                     maximumColumns: limits.spreadsheetColumns)
            }
        }
        return WorkbookSheet(index: index, name: name, cells: cells, mergedRanges: merges)
    }
}
