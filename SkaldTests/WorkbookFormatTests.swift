import Foundation
import XCTest
@testable import Skald

final class WorkbookFormatTests: XCTestCase {
    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent("Corpus/formats"))
            .appendingPathComponent(name)
    }

    private func workbook(_ name: String) throws -> (WorkbookDocument, ConverterOutcome) {
        let outcome = try WorkbookConverter().convertDetailed(at: fixture(name), to: .json)
        let document = try JSONDecoder().decode(WorkbookDocument.self, from: Data(outcome.output.utf8))
        return (document, outcome)
    }

    func testXLSXPreservesOrderSparseTypesFormulaCacheDateAndMerge() throws {
        let (book, outcome) = try workbook("semantic.xlsx")
        XCTAssertEqual(book.version, "2.0")
        XCTAssertEqual(book.sourceFormat, "xlsx")
        XCTAssertEqual(book.sheets.map(\.name), ["Data", "Second"])
        let cells = book.sheets[0].cells
        XCTAssertEqual(cells.map(\.coordinate), ["A1", "C1", "D1", "E1", "F1", "B2", "C3"])
        XCTAssertEqual(cells[0].text, "00123")
        XCTAssertEqual(cells[1].numericLexeme, "9007199254740993")
        XCTAssertEqual(cells[2].type, "boolean")
        XCTAssertEqual(cells[2].text, "true")
        XCTAssertEqual(cells[3].type, "error")
        XCTAssertEqual(cells[3].text, "#DIV/0!")
        XCTAssertEqual(cells[4].type, "date")
        XCTAssertEqual(cells[4].numericLexeme, "44500.5")
        XCTAssertEqual(cells[4].dateEpoch, "1904")
        XCTAssertEqual(cells[4].timezone, "floating")
        XCTAssertNotNil(cells[4].dateValue)
        XCTAssertEqual(cells[5].formula, "A1*2")
        XCTAssertEqual(cells[5].cachedValue, "42")
        XCTAssertEqual(cells[5].cacheStatus, "unverified")
        XCTAssertEqual(book.sheets[0].mergedRanges, ["A1:B1"])
        XCTAssertEqual(book.sheets[1].cells[0].text, "Second sheet")
        XCTAssertEqual(outcome.quality, .partial)
        let markdown = try WorkbookConverter().convert(at: fixture("semantic.xlsx"), to: .markdown)
        XCTAssertTrue(markdown.contains("9007199254740993"))
        XCTAssertTrue(markdown.contains("Worksheet 2"))
        XCTAssertTrue(markdown.contains("~~~json"))
    }

    func testODSPreservesRepeatedSparseCellsPrecisionFormulaDateAndMerge() throws {
        let (book, outcome) = try workbook("semantic.ods")
        XCTAssertEqual(book.sourceFormat, "ods")
        XCTAssertEqual(book.sheets.map(\.name), ["Data", "Second"])
        let cells = book.sheets[0].cells
        XCTAssertEqual(cells.map(\.coordinate), ["A1", "C1", "D1", "C2", "D2"])
        XCTAssertEqual(cells[0].text, "00123")
        XCTAssertEqual(cells[1].numericLexeme, "9007199254740993")
        XCTAssertEqual(cells[2].text, "true")
        XCTAssertEqual(cells[3].formula, "of:=[.A1]*2")
        XCTAssertEqual(cells[3].cachedValue, "42")
        XCTAssertEqual(cells[3].cacheStatus, "unverified")
        XCTAssertEqual(cells[4].dateValue, "2025-03-01T10:30:00")
        XCTAssertEqual(cells[4].dateEpoch, "1899-12-30")
        XCTAssertEqual(cells[4].timezone, "floating")
        XCTAssertEqual(book.sheets[0].mergedRanges, ["A1:B1"])
        XCTAssertEqual(outcome.quality, .partial)
        let markdown = try WorkbookConverter().convert(at: fixture("semantic.ods"), to: .markdown)
        XCTAssertTrue(markdown.contains("9007199254740993"))
        XCTAssertTrue(markdown.contains("Worksheet 2"))
    }

    func testBIFF8XLSReadsCompoundWorkbookCellsFormulaCacheAndMerge() throws {
        let (book, outcome) = try workbook("semantic.xls")
        XCTAssertEqual(book.sourceFormat, "xls-biff8")
        XCTAssertEqual(book.sheets.map(\.name), ["Data", "Second"])
        let cells = book.sheets[0].cells
        XCTAssertEqual(cells.map(\.coordinate), ["A1", "C1", "D1", "E1", "F1", "B2"])
        XCTAssertEqual(cells[0].text, "00123")
        XCTAssertEqual(cells[1].numericLexeme, "1.25")
        XCTAssertEqual(cells[2].text, "true")
        XCTAssertEqual(cells[3].text, "#DIV/0!")
        XCTAssertEqual(cells[4].type, "date")
        XCTAssertEqual(cells[4].dateEpoch, "1904")
        XCTAssertEqual(cells[4].numericLexeme, "44500.5")
        XCTAssertEqual(cells[5].formula, "A1*2")
        XCTAssertEqual(cells[5].cachedValue, "42")
        XCTAssertEqual(cells[5].cacheStatus, "unverified")
        XCTAssertEqual(book.sheets[0].mergedRanges, ["A1:B1"])
        XCTAssertEqual(book.sheets[1].cells[0].text, "Second sheet")
        XCTAssertEqual(outcome.quality, .partial)
        XCTAssertTrue(book.warnings.contains("biff8Subset"))
        let markdown = try WorkbookConverter().convert(at: fixture("semantic.xls"), to: .markdown)
        XCTAssertTrue(markdown.contains("Worksheet 2"))
        XCTAssertTrue(markdown.contains("A1*2"))
    }

    func testNamedWorkbooksRouteThroughRealManager() throws {
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("Skald-Workbook-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: target) }
        let report = try ConversionManager().convertSelections([fixture("semantic.xlsx"), fixture("semantic.xls"), fixture("semantic.ods")],
                                                              to: target, format: .json)
        XCTAssertEqual(report.partialCount, 3)
        XCTAssertEqual(report.failedCount, 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: target, includingPropertiesForKeys: nil).count, 3)
    }

    func testNamedWorkbookExactByteCeilingAndOneByteBelow() throws {
        for name in ["semantic.xlsx", "semantic.xls", "semantic.ods"] {
            let source = try fixture(name)
            let bytes = try Data(contentsOf: source).count
            XCTAssertEqual(try BoundedInputReader.read(source, maximumBytes: bytes).count, bytes, name)
            XCTAssertThrowsError(try BoundedInputReader.read(source, maximumBytes: bytes - 1)) {
                XCTAssertEqual(($0 as? InputDiagnostic)?.code, "inputLimitExceeded", name)
            }
            let expanded = name == "semantic.xls" ? 0 :
                try SafeZipArchive(data: Data(contentsOf: source)).entries.map(\.expandedSize).max() ?? 0
            let ceiling = max(bytes, expanded)
            let atLimit = WorkbookConverter(limits: ResourceLimits(documentInputBytes: ceiling))
            XCTAssertFalse(try atLimit.convert(at: source, to: .json).isEmpty, name)
            let belowLimit = WorkbookConverter(limits: ResourceLimits(documentInputBytes: ceiling - 1))
            XCTAssertThrowsError(try belowLimit.convert(at: source, to: .json)) {
                let inputCode = ($0 as? InputDiagnostic)?.code
                let archiveCode = ($0 as? ZipContainerError)?.code
                XCTAssertEqual(inputCode ?? archiveCode,
                               expanded > bytes ? "archiveExpansionLimitExceeded" : "inputLimitExceeded", name)
            }
        }
    }

    func testExternalEntityEncryptedAndRepeatedVariantsFailWithoutOutput() throws {
        let cases = [
            ("external-relationship.xlsx", "externalLinkDenied"),
            ("entity-declaration.xlsx", "externalEntityDenied"),
            ("encrypted-manifest.ods", "encryptedODSUnsupported"),
            ("repeated-column-limit.ods", "spreadsheetColumnLimitExceeded"),
            ("encrypted.xls", "encryptedXLSUnsupported"),
            ("biff4.xls", "biffVariantUnsupported"),
            ("cross-sheet-eof.xls", "invalidXLS"),
            ("cfb-chain-loop.xls", "cfbChainInvalid")
        ]
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("Skald-Workbook-Negative-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: target) }
        for (name, code) in cases {
            let source = try fixture(name)
            XCTAssertThrowsError(try WorkbookConverter().convert(at: source, to: .json)) {
                XCTAssertEqual(($0 as? InputDiagnostic)?.code, code, name)
            }
            let report = try ConversionManager().convertSelections([source], to: target, format: .json)
            XCTAssertEqual(report.failedCount, 1, name)
            XCTAssertTrue(report.entries[0].message?.contains(code) == true, name)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: target, includingPropertiesForKeys: nil).count, 0)
    }
}
