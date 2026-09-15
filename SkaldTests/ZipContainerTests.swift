import Foundation
import XCTest
@testable import Skald

final class ZipContainerTests: XCTestCase {
    private func fixture(_ name: String) throws -> URL {
        let folder = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent("Corpus/formats"))
        return folder.appendingPathComponent(name)
    }

    private func withTarget(_ body: (URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Skald-ZIP-Test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        try body(folder)
    }

    func testStoredAndDeflatedMembersVerifyAndExtract() throws {
        let archive = try SafeZipArchive(data: Data(contentsOf: fixture("collection.zip")))
        XCTAssertEqual(archive.entries.map(\.path), ["table.csv", "records.json", "opaque.bin", "nested.zip"])
        let csv = try archive.extract(archive.entries[0])
        XCTAssertEqual(String(data: csv, encoding: .utf8), "name,age\nAda,37\n")
        let json = try archive.extract(archive.entries[1])
        let values = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        XCTAssertEqual(values["source"] as? String, "ZIP")
    }

    func testRealRegistryReportsCollectionMembersAndNestedProvenance() throws {
        try withTarget { target in
            let source = try fixture("collection.zip")
            let report = try ConversionManager().convertSelections([source], to: target, format: .json)
            XCTAssertEqual(report.partialCount, 1)
            XCTAssertEqual(report.failedCount, 0)
            let output = try XCTUnwrap(report.entries.first?.outputURL)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Any])
            XCTAssertEqual(object["version"] as? String, "2.0")
            let members = try XCTUnwrap(object["members"] as? [[String: Any]])
            XCTAssertEqual(members.count, 4)
            XCTAssertEqual(members.map { $0["status"] as? String }, ["converted", "converted", "skipped", "converted"])
            XCTAssertTrue((members[3]["path"] as? String)?.contains("nested.zip!/inner.txt") == true)
            let first = try XCTUnwrap(members[0]["content"] as? [String: Any])
            XCTAssertEqual(first["version"] as? String, "2.0")
            let markdown = try ConversionManager().convertSelections([source], to: target, format: .markdown)
            XCTAssertEqual(markdown.partialCount, 1)
            let body = try String(contentsOf: XCTUnwrap(markdown.entries.first?.outputURL), encoding: .utf8)
            XCTAssertTrue(body.contains("Ada"))
            XCTAssertTrue(body.contains("Nested archive text"))
        }
    }

    func testWorkbookMembersUseNamedFormatReadersInsideCollection() throws {
        try withTarget { target in
            let report = try ConversionManager().convertSelections([fixture("workbook-collection.zip")],
                                                                  to: target, format: .json)
            XCTAssertEqual(report.partialCount, 1)
            XCTAssertEqual(report.failedCount, 0)
            let output = try XCTUnwrap(report.entries.first?.outputURL)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Any])
            let members = try XCTUnwrap(object["members"] as? [[String: Any]])
            XCTAssertEqual(members.count, 3)
            XCTAssertEqual(members.map { $0["status"] as? String }, ["partial", "partial", "partial"])
            let formats = members.compactMap { ($0["content"] as? [String: Any])?["sourceFormat"] as? String }
            XCTAssertEqual(formats, ["xlsx", "xls-biff8", "ods"])
            XCTAssertTrue(members.allSatisfy { ($0["path"] as? String)?.contains("books/") == true })
            let markdownReport = try ConversionManager().convertSelections([fixture("workbook-collection.zip")],
                                                                         to: target, format: .markdown)
            XCTAssertEqual(markdownReport.partialCount, 1)
            let markdown = try String(contentsOf: XCTUnwrap(markdownReport.entries.first?.outputURL), encoding: .utf8)
            XCTAssertTrue(markdown.contains("books/semantic.xlsx"))
            XCTAssertTrue(markdown.contains("xls-biff8"))
            XCTAssertTrue(markdown.contains("of:=[.A1]*2"))
        }
    }

    func testUnsafeAndUnsupportedVariantsFailBeforePublication() throws {
        let cases = [
            ("path-traversal.zip", "archivePathDenied"),
            ("absolute-path.zip", "archivePathDenied"),
            ("symlink.zip", "archiveLinkDenied"),
            ("expansion-ratio.zip", "archiveExpansionRatioExceeded"),
            ("encrypted-flag.zip", "encryptedZIPUnsupported"),
            ("zip64-marker.zip", "zip64Unsupported"),
            ("file-directory-collision.zip", "archivePathCollision"),
            ("reserved-name.zip", "archivePathDenied"),
            ("local-header-mismatch.zip", "invalidZIP")
        ]
        try withTarget { target in
            for (name, code) in cases {
                let file = try fixture(name)
                XCTAssertThrowsError(try SafeZipArchive(data: Data(contentsOf: file))) { error in
                    XCTAssertEqual((error as? ZipContainerError)?.code, code, name)
                }
                let report = try ConversionManager().convertSelections([file], to: target, format: .json)
                XCTAssertEqual(report.failedCount, 1, name)
                XCTAssertTrue(report.entries[0].message?.contains(code) == true, name)
            }
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: target, includingPropertiesForKeys: nil).count, 0)
        }
    }

    func testEntryExpansionAndDepthLimits() throws {
        let bytes = try Data(contentsOf: fixture("collection.zip"))
        XCTAssertThrowsError(try SafeZipArchive(data: bytes, maximumEntries: 3)) {
            XCTAssertEqual(($0 as? ZipContainerError)?.code, "archiveEntryLimitExceeded")
        }
        XCTAssertThrowsError(try SafeZipArchive(data: bytes, maximumExpandedBytes: 10)) {
            XCTAssertEqual(($0 as? ZipContainerError)?.code, "archiveExpansionLimitExceeded")
        }
        try withTarget { target in
            let report = try ConversionManager(limits: ResourceLimits(archiveDepth: 1))
                .convertSelections([try fixture("collection.zip")], to: target, format: .json)
            XCTAssertEqual(report.partialCount, 1)
            let file = try XCTUnwrap(report.entries.first?.outputURL)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            let members = try XCTUnwrap(object["members"] as? [[String: Any]])
            XCTAssertEqual(members.last?["status"] as? String, "failed")
            XCTAssertTrue((members.last?["message"] as? String)?.contains("archiveDepthLimitExceeded") == true)
        }
    }

    func testZipExactInputByteLimitAndOneByteBelow() throws {
        let source = try fixture("collection.zip")
        let bytes = try Data(contentsOf: source).count
        try withTarget { target in
            let accepted = try ConversionManager(limits: ResourceLimits(documentInputBytes: bytes))
                .convertSelections([source], to: target, format: .json)
            XCTAssertEqual(accepted.failedCount, 0)
            let rejected = try ConversionManager(limits: ResourceLimits(documentInputBytes: bytes - 1))
                .convertSelections([source], to: target, format: .json)
            XCTAssertEqual(rejected.failedCount, 1)
            XCTAssertTrue(rejected.entries[0].message?.contains("inputLimitExceeded") == true)
        }
    }
}
