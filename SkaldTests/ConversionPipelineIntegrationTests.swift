import Foundation
import XCTest
@testable import Skald

/// These tests invoke the real manager, converter registry and output writer.
/// Establish the isolated baseline crash first; run these after repairing publication.
final class ConversionPipelineIntegrationTests: XCTestCase {
    private func withFolders(_ operation: (URL, URL) throws -> Void) throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("Skald-Regression-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let target = root.appendingPathComponent("target", isDirectory: true)
        try manager.createDirectory(at: source, withIntermediateDirectories: true)
        try manager.createDirectory(at: target, withIntermediateDirectories: true)
        defer {
            do { try manager.removeItem(at: root) }
            catch { XCTFail("Owned temporary fixture cleanup failed: \(error)") }
        }
        try operation(source, target)
    }

    private func seed(_ directory: URL, name: String = "records.csv") throws -> URL {
        let file = directory.appendingPathComponent(name)
        try Data("name,age\nAlice,30\nBob,40\n".utf8).write(to: file, options: .withoutOverwriting)
        return file
    }

    func testRealManagerPublishesMarkdown() throws {
        try withFolders { source, target in
            let input = try seed(source)
            let original = try Data(contentsOf: input)
            let report = try ConversionManager().convertFiles(in: source, to: target, format: .markdown)
            XCTAssertEqual(report.convertedCount, 1)
            XCTAssertEqual(report.failedCount, 0)
            XCTAssertEqual(try Data(contentsOf: input), original)
            let output = target.appendingPathComponent("records.md")
            let text = try String(contentsOf: output, encoding: .utf8)
            XCTAssertTrue(text.contains("Alice"))
            XCTAssertTrue(text.contains("Bob"))
        }
    }

    func testRealManagerPublishesParseableJSON() throws {
        try withFolders { source, target in
            _ = try seed(source)
            let report = try ConversionManager().convertFiles(in: source, to: target, format: .json)
            XCTAssertEqual(report.convertedCount, 1)
            XCTAssertEqual(report.failedCount, 0)
            let output = try Data(contentsOf: target.appendingPathComponent("records.json"))
            let object = try JSONSerialization.jsonObject(with: output)
            XCTAssertNotNil(object as? [String: Any])
            XCTAssertFalse(output.isEmpty)
        }
    }

    func testExistingDestinationRemainsByteIdentical() throws {
        try withFolders { source, target in
            let input = try seed(source)
            let originalSource = try Data(contentsOf: input)
            let existing = target.appendingPathComponent("records.md")
            let sentinel = Data("Existing content must survive.\n".utf8)
            try sentinel.write(to: existing, options: .withoutOverwriting)
            let report = try ConversionManager().convertFiles(in: source, to: target, format: .markdown)
            XCTAssertEqual(report.convertedCount, 1)
            XCTAssertEqual(report.failedCount, 0)
            XCTAssertEqual(try Data(contentsOf: existing), sentinel)
            XCTAssertEqual(try Data(contentsOf: input), originalSource)
            let files = try FileManager.default.contentsOfDirectory(at: target, includingPropertiesForKeys: nil)
            XCTAssertEqual(files.count, 2, "Exactly one additional completed artifact; no temporary leftovers.")
        }
    }

    func testSourceEqualsTargetDoesNotOverwriteOrReingestOutput() throws {
        try withFolders { source, _ in
            let input = source.appendingPathComponent("original.json")
            let original = Data("{\"name\":\"Synthetic\",\"value\":42}".utf8)
            try original.write(to: input, options: .withoutOverwriting)
            let report = try ConversionManager().convertFiles(in: source, to: source, format: .json)
            XCTAssertEqual(report.convertedCount, 1)
            XCTAssertEqual(report.failedCount, 0)
            XCTAssertEqual(try Data(contentsOf: input), original)
            let files = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
            XCTAssertEqual(files.count, 2)
        }
    }

    func testMalformedCSVDoesNotPreventOtherFileConversion() throws {
        try withFolders { source, target in
            _ = try seed(source)
            let broken = source.appendingPathComponent("broken.csv")
            try Data("a,b\n1,\"unterminated\n".utf8).write(to: broken, options: .withoutOverwriting)
            let report = try ConversionManager().convertFiles(in: source, to: target, format: .json)
            XCTAssertEqual(report.convertedCount, 1)
            XCTAssertEqual(report.failedCount, 1)
            XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("broken.json").path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("records.json").path))
        }
    }
}
