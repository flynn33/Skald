import Foundation
import XCTest
@testable import Skald

final class CanonicalTableTests: XCTestCase {
    private func fixture(_ name: String) throws -> URL {
        let root = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent("Corpus/csv"))
        return root.appendingPathComponent(name)
    }

    func testDuplicateBlankAndExtraColumnsStayDistinct() throws {
        for (name, labels, cells) in [
            ("duplicate-headers.csv", ["id", "id"], ["1", "2"]),
            ("blank-headers.csv", ["id", "", ""], ["1", "a", "b"]),
            ("extra-fields.csv", ["a", "b", "Column 3"], ["x", "y", "z"])
        ] {
            let output = try DelimitedTextConverter().convert(at: fixture(name), to: .json, options: DelimitedOptions(header: .present)).output
            let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
            XCTAssertEqual(document["version"] as? String, "2.0", name)
            let content = try XCTUnwrap(document["content"] as? [String: Any])
            let table = try XCTUnwrap(content["canonicalTable"] as? [String: Any])
            let columns = try XCTUnwrap(table["columns"] as? [[String: Any]])
            XCTAssertEqual(columns.compactMap { $0["id"] as? String }, labels.indices.map { "c\($0 + 1)" }, name)
            XCTAssertEqual(columns.compactMap { $0["label"] as? String }, labels, name)
            let records = try XCTUnwrap(table["records"] as? [[String: Any]])
            let values = try XCTUnwrap(records.first?["cells"] as? [Any])
            XCTAssertEqual(values.compactMap { $0 as? String }, cells, name)
            let projection = try XCTUnwrap((content["data"] as? [[String: Any]])?.first)
            for (index, cell) in cells.enumerated() { XCTAssertEqual(projection["c\(index + 1)"] as? String, cell, name) }
        }
    }

    func testMissingAndExplicitEmptyAreDifferent() throws {
        let table = CanonicalDelimitedTable(header: ["a", "b", "c"], rows: [["x", ""], ["", "y", ""]])
        XCTAssertEqual(table.records[0].fieldCount, 2)
        XCTAssertEqual(table.records[0].cells[1], "")
        XCTAssertNil(table.records[0].cells[2])
        XCTAssertEqual(table.records[1].cells[2], "")
        let data = table.dataProjection()
        guard case .array(let records) = data, case .object(let first) = records[0] else { return XCTFail("Projection shape") }
        guard case .string("") = first["c2"], case .null = first["c3"] else { return XCTFail("Empty and missing projection") }
    }

    func testMarkdownIsInertAndJSONRecoverable() throws {
        let table = CanonicalDelimitedTable(header: ["name", "note"], rows: [["00123", "  <script>|[link](https://example.org)\r\n`code`  "], ["", ""]])
        let markdown = try CanonicalDelimitedMarkdown.render(table, settings: nil)
        XCTAssertFalse(markdown.contains("<script>"))
        XCTAssertTrue(markdown.contains("~~~json"))
        XCTAssertTrue(markdown.contains("[link](https://example.org)"))
        XCTAssertTrue(markdown.contains("\\r\\n"))
        XCTAssertTrue(markdown.contains("\"00123\""))
        XCTAssertTrue(markdown.contains("Record 2"))
        let lines = markdown.components(separatedBy: "\n")
        let encodedRecords = lines.enumerated().compactMap { index, line in
            line == "~~~json" && index + 1 < lines.count ? lines[index + 1] : nil
        }
        XCTAssertEqual(encodedRecords.count, 3)
        let recovered = try encodedRecords.dropFirst().map { encoded in
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: String])
        }
        XCTAssertEqual(recovered[0]["c1"], "00123")
        XCTAssertEqual(recovered[0]["c2"], "  <script>|[link](https://example.org)\r\n`code`  ")
        XCTAssertEqual(recovered[1]["c1"], "")
        XCTAssertEqual(recovered[1]["c2"], "")
    }

    func testFenceExceedsSourceRunAndPreservesLiteralMarkup() throws {
        let value = "~~~~~~~ <b>bold</b> [link](https://example.org)"
        let table = CanonicalDelimitedTable(header: ["note"], rows: [[value]])
        let markdown = try CanonicalDelimitedMarkdown.render(table, settings: nil)
        XCTAssertTrue(markdown.contains("~~~~~~~~json"))
        XCTAssertFalse(markdown.contains("<b>"))
        let lines = markdown.components(separatedBy: "\n")
        let opener = try XCTUnwrap(lines.firstIndex(of: "~~~~~~~~json"))
        let record = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(lines[opener + 1].utf8)) as? [String: String])
        XCTAssertEqual(record["c1"], value)
    }

    func testPaddingCorpusPreservesAllRecordsUnderOneMegabyte() throws {
        let output = try DelimitedTextConverter().convert(at: fixture("padding-amplification.csv"), to: .markdown, options: DelimitedOptions(header: .present)).output
        XCTAssertLessThan(output.utf8.count, 1_000_000)
        XCTAssertTrue(output.contains("Record 2000"))
        XCTAssertEqual(output.components(separatedBy: "### Record ").count - 1, 2_000)
    }

    func testIndependentCorpusAgreesAcrossCanonicalJSONAndMarkdown() throws {
        let root = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent("Corpus"))
        let corpus = try JSONDecoder().decode(DelimitedCorpus.self, from: Data(contentsOf: root.appendingPathComponent("csv-cases.json")))
        for item in corpus.cases where item.expectedError == nil && item.expectedParserRows?.isEmpty == false {
            let file = try fixture(URL(fileURLWithPath: item.file).lastPathComponent)
            let encoding: TextEncodingChoice = item.encoding == "cp1252" ? .windows1252 : (item.encoding == "iso8859-1" ? .latin1 : .automatic)
            let delimiter: DelimiterChoice = item.delimiter == "," ? .comma : (item.delimiter == "\t" ? .tab : (item.delimiter == ";" ? .semicolon : .custom(item.delimiter)))
            let options = DelimitedOptions(encoding: encoding, delimiter: delimiter, header: try XCTUnwrap(HeaderMode(rawValue: item.headerMode)))
            let converter = DelimitedTextConverter()
            let json = try converter.convert(at: file, to: .json, options: options).output
            let markdown = try converter.convert(at: file, to: .markdown, options: options).output
            let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
            let content = try XCTUnwrap(document["content"] as? [String: Any])
            let table = try XCTUnwrap(content["canonicalTable"] as? [String: Any])
            let columns = try XCTUnwrap(table["columns"] as? [[String: Any]])
            let records = try XCTUnwrap(table["records"] as? [[String: Any]])
            let expected = try XCTUnwrap(item.expectedDataRows)
            XCTAssertEqual(records.count, expected.count, item.id)
            XCTAssertEqual(columns.count, max(item.expectedOriginalHeader?.count ?? 0, expected.map(\.count).max() ?? 0), item.id)
            let projection = try XCTUnwrap(content["data"] as? [[String: Any]])
            let markdownLines = markdown.components(separatedBy: "\n")
            let encodedBlocks = markdownLines.enumerated().compactMap { index, line in
                line.first == "~" && line.hasSuffix("json") && index + 1 < markdownLines.count ? markdownLines[index + 1] : nil
            }
            XCTAssertEqual(encodedBlocks.count, expected.count + 1, item.id)
            let markdownColumns = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(encodedBlocks[0].utf8)) as? [[String: Any]])
            XCTAssertEqual(markdownColumns.compactMap { $0["id"] as? String }, columns.compactMap { $0["id"] as? String }, item.id)
            for (index, row) in expected.enumerated() {
                XCTAssertEqual(records[index]["fieldCount"] as? Int, row.count, item.id)
                let cells = try XCTUnwrap(records[index]["cells"] as? [Any])
                let markdownRecord = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(encodedBlocks[index + 1].utf8)) as? [String: Any])
                for (columnIndex, column) in columns.enumerated() {
                    let id = try XCTUnwrap(column["id"] as? String)
                    if columnIndex < row.count {
                        XCTAssertEqual(cells[columnIndex] as? String, row[columnIndex], item.id)
                        XCTAssertEqual(projection[index][id] as? String, row[columnIndex], item.id)
                        XCTAssertEqual(markdownRecord[id] as? String, row[columnIndex], item.id)
                    } else {
                        XCTAssertTrue(cells[columnIndex] is NSNull, item.id)
                        XCTAssertTrue(projection[index][id] is NSNull, item.id)
                        XCTAssertTrue(markdownRecord[id] is NSNull, item.id)
                    }
                }
            }
        }
    }
}
