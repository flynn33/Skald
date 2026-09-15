import Foundation

nonisolated struct ResourceLimits: Sendable {
    let textInputBytes: Int
    let structuredInputBytes: Int
    let delimitedInputBytes: Int
    let documentInputBytes: Int
    let imageInputBytes: Int
    let delimitedRecords: Int
    let delimitedColumns: Int
    let delimitedCells: Int
    let delimitedFieldScalars: Int
    let nestingDepth: Int
    let valueNodes: Int
    let imageSourcePixels: UInt64
    let archiveEntries: Int
    let archiveDepth: Int
    let archiveExpandedBytes: Int
    let spreadsheetSheets: Int
    let spreadsheetRows: Int
    let spreadsheetColumns: Int
    let spreadsheetCells: Int
    let totalWorkBytes: Int
    let outputBytes: Int
    let workItems: Int

    init(
        textInputBytes: Int = 16 * 1_024 * 1_024,
        structuredInputBytes: Int = 16 * 1_024 * 1_024,
        delimitedInputBytes: Int = 64 * 1_024 * 1_024,
        documentInputBytes: Int = 64 * 1_024 * 1_024,
        imageInputBytes: Int = 64 * 1_024 * 1_024,
        delimitedRecords: Int = 100_000,
        delimitedColumns: Int = 1_024,
        delimitedCells: Int = 250_000,
        delimitedFieldScalars: Int = 1_000_000,
        nestingDepth: Int = 64,
        valueNodes: Int = 100_000,
        imageSourcePixels: UInt64 = 40_000_000,
        archiveEntries: Int = 1_000,
        archiveDepth: Int = 2,
        archiveExpandedBytes: Int = 256 * 1_024 * 1_024,
        spreadsheetSheets: Int = 128,
        spreadsheetRows: Int = 100_000,
        spreadsheetColumns: Int = 1_024,
        spreadsheetCells: Int = 250_000,
        totalWorkBytes: Int = 512 * 1_024 * 1_024,
        outputBytes: Int = 128 * 1_024 * 1_024,
        workItems: Int = 10_000
    ) {
        self.textInputBytes = textInputBytes
        self.structuredInputBytes = structuredInputBytes
        self.delimitedInputBytes = delimitedInputBytes
        self.documentInputBytes = documentInputBytes
        self.imageInputBytes = imageInputBytes
        self.delimitedRecords = delimitedRecords
        self.delimitedColumns = delimitedColumns
        self.delimitedCells = delimitedCells
        self.delimitedFieldScalars = delimitedFieldScalars
        self.nestingDepth = nestingDepth
        self.valueNodes = valueNodes
        self.imageSourcePixels = imageSourcePixels
        self.archiveEntries = archiveEntries
        self.archiveDepth = archiveDepth
        self.archiveExpandedBytes = archiveExpandedBytes
        self.spreadsheetSheets = spreadsheetSheets
        self.spreadsheetRows = spreadsheetRows
        self.spreadsheetColumns = spreadsheetColumns
        self.spreadsheetCells = spreadsheetCells
        self.totalWorkBytes = totalWorkBytes
        self.outputBytes = outputBytes
        self.workItems = workItems
    }

    func validate() throws {
        let values = [textInputBytes, structuredInputBytes, delimitedInputBytes, documentInputBytes, imageInputBytes, delimitedRecords,
                      delimitedColumns, delimitedCells, delimitedFieldScalars, nestingDepth, valueNodes,
                      archiveEntries, archiveDepth, archiveExpandedBytes, spreadsheetSheets, spreadsheetRows,
                      spreadsheetColumns, spreadsheetCells, totalWorkBytes, outputBytes, workItems]
        guard values.allSatisfy({ $0 > 0 }), imageSourcePixels > 0 else {
            throw InputDiagnostic(code: "invalidLimitConfiguration", stage: "configure", summary: "Every configured resource limit must be positive.")
        }
    }
}
