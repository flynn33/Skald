import CryptoKit
import Foundation
import XCTest
@testable import Skald

final class DelimitedCorpusTests: XCTestCase {
    private func corpusRoot() throws -> URL {
        let root = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent("Corpus"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("csv-cases.json").path), "The independent corpus must be in the native test bundle.")
        return root
    }

    func testAllIndependentByteCases() throws {
        let root = try corpusRoot()
        let corpus = try JSONDecoder().decode(DelimitedCorpus.self, from: Data(contentsOf: root.appendingPathComponent("csv-cases.json")))
        XCTAssertEqual(corpus.cases.count, 34)
        for item in corpus.cases {
            let data = try Data(contentsOf: root.appendingPathComponent("csv").appendingPathComponent(URL(fileURLWithPath: item.file).lastPathComponent))
            XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), item.sha256, item.id)
            let choice: TextEncodingChoice = {
                switch item.encoding {
                case "cp1252": return .windows1252
                case "iso8859-1": return .latin1
                default: return .automatic
                }
            }()
            do {
                let decoded = try TextDecoder().decode(data, choice: choice)
                let delimiter = try XCTUnwrap(item.delimiter.unicodeScalars.first)
                let rows = try DelimitedTextParser().parse(decoded.text, delimiter: delimiter, chunkSize: 1)
                XCTAssertNil(item.expectedError, item.id)
                XCTAssertEqual(rows, item.expectedParserRows, item.id)
                let mode = try XCTUnwrap(HeaderMode(rawValue: item.headerMode))
                let interpreted = DelimitedTextInterpreter().interpret(rows: rows, headerMode: mode)
                XCTAssertEqual(interpreted.dataRows, item.expectedDataRows, item.id)
                XCTAssertEqual(interpreted.originalHeader, item.expectedOriginalHeader, item.id)
                XCTAssertEqual(Set(interpreted.diagnostics.map(\.code)), Set(item.expectedDiagnostics), item.id)
            } catch let error as DelimitedInputError {
                XCTAssertEqual(error.code, item.expectedError, item.id)
            }
        }
    }

    func testOneThousandSeededRoundTripsAcrossChunkSizes() throws {
        var state: UInt64 = 0x5ca1d2026
        func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state }
        let values = ["plain", "  spaced  ", "a,b", "one\"quote", "line\nfeed", "cr\rreturn", "pair\r\nline", "Æsir", "零", "00123", "=SUM(A1:A2)", ""]
        for caseIndex in 0..<1_000 {
            let rowCount = Int(next() % 5) + 1
            let columnCount = Int(next() % 5) + 1
            let records = (0..<rowCount).map { _ in (0..<columnCount).map { _ in values[Int(next() % UInt64(values.count))] } }
            let newline = ["\n", "\r", "\r\n"][caseIndex % 3]
            let encoded = records.map { row in
                row.map { value -> String in
                    if value.unicodeScalars.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
                        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                    }
                    return value
                }.joined(separator: ",")
            }.joined(separator: newline) + newline
            for chunkSize in [1, 2, 3, 7, 4_096] {
                XCTAssertEqual(try DelimitedTextParser().parse(encoded, delimiter: ",", chunkSize: chunkSize), records, "seed=0x5ca1d2026 case=\(caseIndex) chunk=\(chunkSize)")
            }
        }
    }

    func testExplicitEncodingHeaderAndDelimiterReachRealManager() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Skald-Delimited-Options-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let target = root.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = source.appendingPathComponent("records.csv")
        try Data([0x61, 0x3b, 0x62, 0x0a, 0x31, 0x3b, 0x93, 0x78, 0x94, 0x0a]).write(to: input)
        let options = DelimitedOptions(encoding: .windows1252, delimiter: .semicolon, header: .absent)
        let report = try ConversionManager().convertFiles(in: source, to: target, format: .json, delimitedOptions: options)
        XCTAssertEqual(report.convertedCount, 1)
        let output = try Data(contentsOf: target.appendingPathComponent("records.json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: output) as? [String: Any])
        let sourceMetadata = try XCTUnwrap(object["source"] as? [String: Any])
        let settings = try XCTUnwrap(sourceMetadata["importSettings"] as? [String: Any])
        XCTAssertEqual(settings["encoding"] as? String, "windows-1252")
        XCTAssertEqual(settings["delimiter"] as? String, ";")
        XCTAssertEqual(settings["headerMode"] as? String, "absent")
        let content = try XCTUnwrap(object["content"] as? [String: Any])
        let table = try XCTUnwrap(content["canonicalTable"] as? [String: Any])
        let records = try XCTUnwrap(table["records"] as? [[String: Any]])
        let rows = try records.map { try XCTUnwrap($0["cells"] as? [String]) }
        XCTAssertEqual(rows, [["a", "b"], ["1", "“x”"]])
    }
    func testByteReadBoundariesAcrossBOMUnicodeCRLFAndQuotes() throws {
        let root = try corpusRoot()
        let corpus = try JSONDecoder().decode(DelimitedCorpus.self, from: Data(contentsOf: root.appendingPathComponent("csv-cases.json")))
        let selected = Set(["C02", "C05", "C06", "C08", "C10", "C24", "C26", "C34"])
        for item in corpus.cases where selected.contains(item.id) {
            let file = root.appendingPathComponent("csv").appendingPathComponent(URL(fileURLWithPath: item.file).lastPathComponent)
            let choice: TextEncodingChoice = item.encoding == "cp1252" ? .windows1252 : .automatic
            for size in [1, 2, 3, 7, 4_096] {
                let decoded = try TextDecoder(readChunkSize: size).read(file, choice: choice)
                let delimiter = try XCTUnwrap(item.delimiter.unicodeScalars.first)
                XCTAssertEqual(try DelimitedTextParser().parse(decoded.text, delimiter: delimiter, chunkSize: size), item.expectedParserRows, "\(item.id) byte/scalar chunk=\(size)")
            }
        }
    }

    func testAutomaticHeaderKeepsFirstRecordThroughManager() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Skald-Header-Auto-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let target = root.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("name,code\nAva,00123\n".utf8).write(to: source.appendingPathComponent("records.csv"))
        let report = try ConversionManager().convertFiles(in: source, to: target, format: .json)
        XCTAssertEqual(report.convertedCount, 1)
        XCTAssertTrue(report.entries[0].message?.contains("headerUnconfirmed") == true)
        let output = try JSONSerialization.jsonObject(with: Data(contentsOf: target.appendingPathComponent("records.json"))) as? [String: Any]
        let content = try XCTUnwrap(output?["content"] as? [String: Any])
        let table = try XCTUnwrap(content["canonicalTable"] as? [String: Any])
        let records = try XCTUnwrap(table["records"] as? [[String: Any]])
        XCTAssertEqual(records.compactMap { $0["cells"] as? [String] }, [["name", "code"], ["Ava", "00123"]])
    }

    func testInvalidUTF8AndMalformedQuotesPublishNoNormalOutput() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Skald-Delimited-Negative-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let target = root.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0x61, 0x2C, 0xFF, 0x0A]).write(to: source.appendingPathComponent("bad-encoding.csv"))
        try Data("a,b\n1,\"unterminated".utf8).write(to: source.appendingPathComponent("bad-quote.csv"))
        let report = try ConversionManager().convertFiles(in: source, to: target, format: .json)
        XCTAssertEqual(report.failedCount, 2)
        XCTAssertEqual(report.convertedCount, 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.path).count, 0)
        XCTAssertTrue(report.entries.contains(where: { $0.message?.contains("invalidEncoding") == true }))
        XCTAssertTrue(report.entries.contains(where: { $0.message?.contains("malformedDelimitedText") == true }))
    }

    func testConfiguredByteLimitRejectsBeforeDecode() throws {
        let decoder = TextDecoder(maximumInputBytes: 3)
        XCTAssertThrowsError(try decoder.decode(Data("four".utf8), choice: .utf8)) { error in
            guard let diagnostic = error as? DelimitedInputError else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(diagnostic.code, "inputLimitExceeded")
        }
    }
    func testSepPreambleRequiresExplicitOptionAndPreservesDataOtherwise() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Skald-Sep-Preamble-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let target = root.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("sep=;\r\nname;code\r\nAva;00123\r\n".utf8).write(to: source.appendingPathComponent("records.csv"))
        let defaultReport = try ConversionManager().convertFiles(in: source, to: target, format: .json, delimitedOptions: DelimitedOptions(header: .absent))
        XCTAssertEqual(defaultReport.convertedCount, 1)
        let defaultJSON = try JSONSerialization.jsonObject(with: Data(contentsOf: target.appendingPathComponent("records.json"))) as? [String: Any]
        let defaultContent = try XCTUnwrap(defaultJSON?["content"] as? [String: Any])
        let defaultTable = try XCTUnwrap(defaultContent["canonicalTable"] as? [String: Any])
        XCTAssertEqual((defaultTable["records"] as? [[String: Any]])?.first?["cells"] as? [String], ["sep=", ""])

        let explicit = DelimitedOptions(delimiter: .semicolon, header: .present, allowSepPreamble: true)
        let explicitReport = try ConversionManager().convertFiles(in: source, to: target, format: .json, delimitedOptions: explicit)
        XCTAssertEqual(explicitReport.convertedCount, 1)
        let qualified = try XCTUnwrap(explicitReport.entries[0].outputURL)
        let explicitJSON = try JSONSerialization.jsonObject(with: Data(contentsOf: qualified)) as? [String: Any]
        let explicitContent = try XCTUnwrap(explicitJSON?["content"] as? [String: Any])
        let explicitTable = try XCTUnwrap(explicitContent["canonicalTable"] as? [String: Any])
        XCTAssertEqual((explicitTable["records"] as? [[String: Any]])?.compactMap { $0["cells"] as? [String] }, [["Ava", "00123"]])
    }

    func testCustomDelimiterMustBeOneValidScalar() throws {
        let rows = try DelimitedTextParser().parse("a|b\n1|2\n", delimiter: "|", chunkSize: 1)
        XCTAssertEqual(rows, [["a", "b"], ["1", "2"]])
        XCTAssertThrowsError(try DelimitedTextParser().parse("a,b\n", delimiter: "\r\n")) { error in
            XCTAssertEqual((error as? DelimitedInputError)?.code, "invalidDelimiter")
        }
    }
    func testZeroByteCSVHasEmptyOutcomeThroughManager() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Skald-Empty-CSV-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let target = root.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: source.appendingPathComponent("empty.csv"))
        let report = try ConversionManager().convertFiles(in: source, to: target, format: .json)
        XCTAssertEqual(report.convertedCount, 0)
        XCTAssertEqual(report.emptyCount, 1)
        XCTAssertEqual(report.entries[0].status, .empty)
        let output = try Data(contentsOf: target.appendingPathComponent("empty.json"))
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: output) as? [String: Any])
        let metadata = try XCTUnwrap(document["source"] as? [String: Any])
        let settings = try XCTUnwrap(metadata["importSettings"] as? [String: Any])
        XCTAssertTrue((settings["diagnostics"] as? [String])?.contains("emptyInput") == true)
    }

    func testMalformedUTF16UTF32AndUndefinedWindows1252AreStrictErrors() throws {
        let decoder = TextDecoder()
        let invalidCases: [(Data, TextEncodingChoice)] = [
            (Data([0xFF, 0xFE, 0x00, 0xD8]), .automatic),
            (Data([0x00, 0x00, 0xFE, 0xFF, 0x00, 0x00, 0xD8, 0x00]), .automatic),
            (Data([0x81]), .windows1252)
        ]
        for (bytes, choice) in invalidCases {
            XCTAssertThrowsError(try decoder.decode(bytes, choice: choice)) { error in
                XCTAssertEqual((error as? DelimitedInputError)?.code, "invalidEncoding")
            }
        }
        let emoji = try decoder.decode(Data([0xFF, 0xFE, 0x3D, 0xD8, 0x00, 0xDE]), choice: .automatic)
        XCTAssertEqual(emoji.text, "😀")
    }
}
