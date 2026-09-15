import Darwin
import Foundation
import XCTest
@testable import Skald

final class ResourceBoundsTests: XCTestCase {
    private func withFolders(_ body: (URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Skald-Bounds-\(UUID().uuidString)")
        let source = root.appendingPathComponent("source")
        let target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(source, target)
    }

    private func code(_ error: Error) -> String? {
        (error as? InputDiagnostic)?.code ?? (error as? DelimitedInputError)?.code
    }

    func testDelimitedRecordColumnAndFieldLimitsIdentifyBoundary() throws {
        let recordParser = DelimitedTextParser(maximumRecords: 1)
        XCTAssertThrowsError(try recordParser.parse("a\nb\n", delimiter: ",")) { XCTAssertEqual(self.code($0), "recordLimitExceeded") }
        let columnParser = DelimitedTextParser(maximumColumns: 1)
        XCTAssertThrowsError(try columnParser.parse("a,b\n", delimiter: ",")) { XCTAssertEqual(self.code($0), "columnLimitExceeded") }
        let fieldParser = DelimitedTextParser(maximumFieldScalars: 2)
        XCTAssertThrowsError(try fieldParser.parse("abc\n", delimiter: ",")) { XCTAssertEqual(self.code($0), "fieldLimitExceeded") }
        let cellParser = DelimitedTextParser(maximumCells: 2)
        XCTAssertThrowsError(try cellParser.parse("a,b\nc\n", delimiter: ",")) { XCTAssertEqual(self.code($0), "cellLimitExceeded") }
    }

    func testReaderRejectsBeforeLoadingAndExactLimitIsAccepted() throws {
        try withFolders { source, _ in
            let file = source.appendingPathComponent("sample.txt")
            try Data("123456".utf8).write(to: file)
            XCTAssertEqual(try BoundedInputReader.read(file, maximumBytes: 6, chunkBytes: 2), Data("123456".utf8))
            XCTAssertThrowsError(try BoundedInputReader.read(file, maximumBytes: 5)) { XCTAssertEqual(self.code($0), "inputLimitExceeded") }
        }
    }

    func testJSONNodeAndDepthLimitsAreTyped() throws {
        try withFolders { source, _ in
            let file = source.appendingPathComponent("sample.json")
            try Data("{\"a\":[1,2]}".utf8).write(to: file)
            XCTAssertThrowsError(try JSONConverter(maximumNodes: 2).convert(at: file, to: .json)) { XCTAssertEqual(self.code($0), "nodeLimitExceeded") }
            XCTAssertThrowsError(try JSONConverter(maximumDepth: 2).convert(at: file, to: .json)) { XCTAssertEqual(self.code($0), "depthLimitExceeded") }
        }
    }

    func testMalformedJSONPreservesCauseWithoutEchoingContent() throws {
        try withFolders { source, _ in
            let secret = "PRIVATE_SENTINEL_98765"
            let file = source.appendingPathComponent("sample.json")
            try Data("{\"password\":\"\(secret)".utf8).write(to: file)
            XCTAssertThrowsError(try JSONConverter().convert(at: file, to: .json)) { error in
                let diagnostic = error as? InputDiagnostic
                XCTAssertEqual(diagnostic?.code, "malformedJSON")
                XCTAssertNotNil(diagnostic?.underlying)
                XCTAssertFalse(error.localizedDescription.contains(secret))
            }
        }
    }

    func testBatchAndOutputLimitsFailExplicitlyWithoutArtifacts() throws {
        try withFolders { source, target in
            let file = source.appendingPathComponent("sample.json")
            try Data("{\"x\":1}".utf8).write(to: file)
            let intake = try ConversionManager(limits: ResourceLimits(totalWorkBytes: 5)).convertFiles(in: source, to: target, format: .json)
            XCTAssertEqual(intake.failedCount, 1)
            XCTAssertTrue(intake.entries[0].message?.contains("totalWorkLimitExceeded") == true)
            let output = try ConversionManager(limits: ResourceLimits(outputBytes: 5)).convertFiles(in: source, to: target, format: .json)
            XCTAssertEqual(output.failedCount, 1)
            XCTAssertTrue(output.entries[0].message?.contains("outputLimitExceeded") == true)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: target, includingPropertiesForKeys: nil).count, 0)
        }
    }

    func testInvalidLimitConfigurationStopsRun() throws {
        try withFolders { source, target in
            XCTAssertThrowsError(try ConversionManager(limits: ResourceLimits(outputBytes: 0))
                .convertFiles(in: source, to: target, format: .json)) { XCTAssertEqual(self.code($0), "invalidLimitConfiguration") }
        }
    }

    func testResourceBearingHTMLAndMarkdownMarkupRemainInert() throws {
        try withFolders { source, _ in
            let html = source.appendingPathComponent("resource.html")
            try Data("<html><body><img src=file:///private/secret></body></html>".utf8).write(to: html)
            XCTAssertThrowsError(try AttributedDocumentConverter().convert(at: html, to: .markdown)) {
                XCTAssertEqual(($0 as? AttributedInputError)?.code, "externalResourceDenied")
            }
            let text = "<img src=\"https://example.org/x\"> ![x](https://example.org/x) [link](https://example.org)"
            let block = ReadableBlock(order: 1, type: .paragraph, text: text, headingLevel: nil,
                                      listStyle: nil, listDepth: nil, listIndex: nil)
            let markdown = ReadableOutputFormatter.markdownDocument(title: "untrusted", blocks: [block])
            XCTAssertFalse(markdown.contains("<img"))
            XCTAssertFalse(markdown.contains("![x]("))
            XCTAssertFalse(markdown.contains("[link]("))
        }
    }

    func testSustainedBatchHasBoundedProgressAndNoTemporaryArtifacts() throws {
        try withFolders { source, target in
            for index in 0..<100 {
                let file = source.appendingPathComponent(String(format: "record-%03d.json", index))
                try Data("{\"item\":\(index)}".utf8).write(to: file)
            }
            var progress: [(Int, Int)] = []
            let started = Date()
            let report = try ConversionManager().convertSelections([source], to: target, format: .json, progress: { completed, total in
                progress.append((completed, total))
            })
            let elapsed = Date().timeIntervalSince(started)
            var usage = rusage()
            _ = getrusage(RUSAGE_SELF, &usage)
            print(String(format: "P06 batch: 100 files, %.3f s, peak RSS %ld bytes", elapsed, usage.ru_maxrss))
            XCTAssertEqual(report.convertedCount, 100)
            XCTAssertEqual(report.failedCount, 0)
            XCTAssertEqual(progress.last?.0, 100)
            XCTAssertEqual(progress.last?.1, 100)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: target, includingPropertiesForKeys: nil).count, 100)
            XCTAssertLessThan(elapsed, 30)
        }
    }

    func test2000RecordCorpusThroughputAndPeakRSS() throws {
        let root = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent("Corpus/csv"))
        let input = root.appendingPathComponent("padding-amplification.csv")
        let started = Date()
        let output = try DelimitedTextConverter().convert(at: input, to: .markdown,
                                                          options: DelimitedOptions(header: .present)).output
        let elapsed = Date().timeIntervalSince(started)
        var usage = rusage()
        _ = getrusage(RUSAGE_SELF, &usage)
        print(String(format: "P06 corpus: 2000 records, %d output bytes, %.3f s, peak RSS %ld bytes",
                     output.utf8.count, elapsed, usage.ru_maxrss))
        XCTAssertLessThan(output.utf8.count, 1_000_000)
        XCTAssertEqual(output.components(separatedBy: "### Record ").count - 1, 2_000)
    }

    func testReadCancellationStopsBeforeFullFileLoad() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Skald-Cancel-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 65, count: 8 * 1_024 * 1_024).write(to: root)
        let task = Task.detached(priority: .utility) {
            try BoundedInputReader.read(root, maximumBytes: 8 * 1_024 * 1_024, chunkBytes: 16)
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("A cancelled read completed as a full input.")
        } catch OutputPublicationError.cancelled {
            // The handle is closed by the bounded reader's defer path.
        }
    }
}
