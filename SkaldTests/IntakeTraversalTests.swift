import Darwin
import Foundation
import XCTest
@testable import Skald

final class IntakeTraversalTests: XCTestCase {
    private final class BlockingTextConverter: DocumentConverter {
        let supportedExtensions = ["txt"]
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        func convert(at url: URL, to format: OutputFormat) throws -> String {
            entered.signal()
            _ = release.wait(timeout: .now() + 5)
            return "# Waited\n"
        }
    }
    private func withFolders(_ body: (URL, URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Skald-Intake-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let target = root.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root, source, target)
    }

    func testDirectFileMultipleSelectionsAndDuplicateIdentity() throws {
        try withFolders { _, source, target in
            let a = source.appendingPathComponent("one.csv")
            let b = source.appendingPathComponent("two.csv")
            try Data("a,b\n1,2\n".utf8).write(to: a)
            try Data("c,d\n3,4\n".utf8).write(to: b)
            let worklist = try SourceWorklistBuilder().snapshot(selections: [a, b, a], target: target, options: IntakeOptions())
            XCTAssertEqual(worklist.items.filter(\.isConvertible).count, 2)
            XCTAssertTrue(worklist.items.contains { $0.message?.contains("Duplicate") == true })
            let report = try ConversionManager().convertSelections([a, b], to: target, format: .json)
            XCTAssertEqual(report.convertedCount, 2)
        }
    }

    func testRecursiveToggleNestedTargetAndDotfile() throws {
        try withFolders { _, source, _ in
            let nested = source.appendingPathComponent("nested", isDirectory: true)
            let target = nested.appendingPathComponent("outputs", isDirectory: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            try Data("a,b\n1,2\n".utf8).write(to: nested.appendingPathComponent("records.csv"))
            try Data("x=1\n".utf8).write(to: source.appendingPathComponent(".env"))
            try Data("old\n".utf8).write(to: target.appendingPathComponent("old.txt"))
            let flat = try SourceWorklistBuilder().snapshot(selections: [source], target: target, options: IntakeOptions())
            XCTAssertEqual(flat.items.filter(\.isConvertible).map { $0.url.lastPathComponent }, [".env"])
            let recursive = try SourceWorklistBuilder().snapshot(selections: [source], target: target, options: IntakeOptions(recursive: true))
            XCTAssertEqual(Set(recursive.items.filter(\.isConvertible).map { $0.url.lastPathComponent }), Set([".env", "records.csv"]))
            XCTAssertFalse(recursive.items.contains { $0.url.lastPathComponent == "old.txt" })
        }
    }

    func testPackageSymlinkAndSpecialFileDoNotDescendOrBlock() throws {
        try withFolders { _, source, target in
            let package = source.appendingPathComponent("letter.rtfd", isDirectory: true)
            try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
            try Data("{\\rtf1 hello}".utf8).write(to: package.appendingPathComponent("TXT.rtf"))
            let link = source.appendingPathComponent("loop")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
            let fifo = source.appendingPathComponent("pipe.txt")
            XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
            let list = try SourceWorklistBuilder().snapshot(selections: [source], target: target, options: IntakeOptions(recursive: true))
            XCTAssertTrue(list.items.contains { $0.url.lastPathComponent == package.lastPathComponent && $0.isConvertible })
            XCTAssertFalse(list.items.contains { $0.url.lastPathComponent == "TXT.rtf" })
            XCTAssertTrue(list.items.contains { $0.url.lastPathComponent == link.lastPathComponent && $0.message?.contains("Symbolic") == true })
            XCTAssertTrue(list.items.contains { $0.url.lastPathComponent == fifo.lastPathComponent && $0.message?.contains("Special") == true })
            let report = try ConversionManager().convertSelections([package], to: target, format: .json)
            XCTAssertEqual(report.convertedCount, 1)
        }
    }

    func testExtensionlessStrictTextAndBinaryClassification() throws {
        try withFolders { _, source, target in
            let readable = source.appendingPathComponent("README")
            let binary = source.appendingPathComponent("unknown.bin")
            try Data("# Note\nBody\n".utf8).write(to: readable)
            try Data([0, 0xFF, 0x8A]).write(to: binary)
            let report = try ConversionManager().convertSelections([readable, binary], to: target, format: .json)
            XCTAssertEqual(report.convertedCount, 1)
            XCTAssertEqual(report.skippedCount + report.failedCount, 1)
            XCTAssertTrue(report.entries.contains { $0.fileName == "README" && $0.status == .converted })
            XCTAssertTrue(report.entries.contains { $0.fileName == "unknown" && $0.message?.contains("binary") == true })
        }
    }

    func testSameTargetSnapshotPreservesOriginalInputs() throws {
        try withFolders { _, source, _ in
            try Data("a,b\n1,2\n".utf8).write(to: source.appendingPathComponent("records.csv"))
            let report = try ConversionManager().convertSelections([source], to: source, format: .json)
            XCTAssertEqual(report.convertedCount, 1)
            XCTAssertEqual(report.totalCount, 1)
        }
    }

    func testServiceRejectsConcurrentStartAndAllowsSecondRun() throws {
        try withFolders { _, source, target in
            let file = source.appendingPathComponent("slow.txt")
            try Data("hello\n".utf8).write(to: file)
            let blocker = BlockingTextConverter()
            let manager = ConversionManager(converters: [blocker])
            let done = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                defer { done.signal() }
                _ = try? manager.convertSelections([file], to: target, format: .markdown)
            }
            XCTAssertEqual(blocker.entered.wait(timeout: .now() + 5), .success)
            XCTAssertThrowsError(try manager.convertSelections([file], to: target, format: .markdown)) { error in
                guard case IntakeError.alreadyRunning = error else { return XCTFail("Unexpected error: \(error)") }
            }
            blocker.release.signal()
            XCTAssertEqual(done.wait(timeout: .now() + 5), .success)
            blocker.release.signal()
            XCTAssertEqual(try manager.convertSelections([file], to: target, format: .markdown).convertedCount, 1)
        }
    }

    func testCancellationPreservesCommittedFirstOutputAndStopsNewWork() throws {
        try withFolders { _, source, target in
            let a = source.appendingPathComponent("a.csv")
            let b = source.appendingPathComponent("b.csv")
            try Data("x,y\n1,2\n".utf8).write(to: a)
            try Data("x,y\n3,4\n".utf8).write(to: b)
            var cancel = false
            let report = try ConversionManager().convertSelections([a, b], to: target, format: .json, progress: { position, _ in
                if position == 1 { cancel = true }
            }, isCancelled: { cancel })
            XCTAssertTrue(report.wasCancelled)
            XCTAssertEqual(report.convertedCount, 1)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.path).count, 1)
        }
    }

    func testExtensionConflictAndUnknownTextAreExplicit() throws {
        try withFolders { _, source, target in
            let conflict = source.appendingPathComponent("fake.csv")
            let unknown = source.appendingPathComponent("notes.odd")
            try Data("%PDF-1.7\n".utf8).write(to: conflict)
            try Data("# Notes\nPlain text\n".utf8).write(to: unknown)
            let report = try ConversionManager().convertSelections([conflict, unknown], to: target, format: .json)
            XCTAssertEqual(report.failedCount, 1)
            XCTAssertEqual(report.convertedCount, 1)
            XCTAssertTrue(report.entries.contains { $0.message?.contains("extensionContentMismatch") == true })
        }
    }

    func testUnreadableSourceReportsFailureWithoutPublishing() throws {
        try withFolders { _, source, target in
            let denied = source.appendingPathComponent("denied.txt")
            try Data("private\n".utf8).write(to: denied)
            XCTAssertEqual(chmod(denied.path, 0), 0)
            defer { _ = chmod(denied.path, 0o600) }
            let report = try ConversionManager().convertSelections([denied], to: target, format: .json)
            XCTAssertEqual(report.failedCount, 1)
            XCTAssertEqual(report.convertedCount, 0)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.path).count, 0)
        }
    }

    func testBOMEncodedCSVPassesContentProbeAndParser() throws {
        try withFolders { _, source, target in
            let file = source.appendingPathComponent("utf16.csv")
            try Data([0xFF, 0xFE, 0x61, 0x00, 0x2C, 0x00, 0x62, 0x00, 0x0A, 0x00, 0x31, 0x00, 0x2C, 0x00, 0x32, 0x00, 0x0A, 0x00]).write(to: file)
            let report = try ConversionManager().convertSelections([file], to: target, format: .json)
            XCTAssertEqual(report.convertedCount, 1)
            XCTAssertEqual(report.failedCount, 0)
        }
    }

    func testExplicitHiddenFileIsHonoredAndRecursiveHiddenToggleControlsDiscovery() throws {
        try withFolders { _, source, target in
            let hidden = source.appendingPathComponent(".secret.odd")
            try Data("# Hidden note\n".utf8).write(to: hidden)
            let defaultList = try SourceWorklistBuilder().snapshot(selections: [source], target: target, options: IntakeOptions())
            XCTAssertTrue(defaultList.items.contains { $0.url.lastPathComponent == hidden.lastPathComponent && !$0.isConvertible })
            let includedList = try SourceWorklistBuilder().snapshot(selections: [source], target: target, options: IntakeOptions(includeHidden: true))
            XCTAssertTrue(includedList.items.contains { $0.url.lastPathComponent == hidden.lastPathComponent && $0.isConvertible })
            let report = try ConversionManager().convertSelections([hidden], to: target, format: .json)
            XCTAssertEqual(report.convertedCount, 1)
        }
    }

    func testAppBundleIsSkippedAndHardlinkAliasDeduplicated() throws {
        try withFolders { _, source, target in
            let app = source.appendingPathComponent("Unused.app", isDirectory: true)
            try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
            try Data("inside\n".utf8).write(to: app.appendingPathComponent("inside.txt"))
            let first = source.appendingPathComponent("first.txt")
            let alias = source.appendingPathComponent("alias.txt")
            try Data("text\n".utf8).write(to: first)
            try FileManager.default.linkItem(at: first, to: alias)
            let list = try SourceWorklistBuilder().snapshot(selections: [source], target: target, options: IntakeOptions(recursive: true))
            XCTAssertFalse(list.items.contains { $0.url.lastPathComponent == "inside.txt" })
            XCTAssertTrue(list.items.contains { $0.url.lastPathComponent == "Unused.app" && $0.message?.contains("Application/package") == true })
            XCTAssertEqual(list.items.filter(\.isConvertible).count, 1)
            XCTAssertTrue(list.items.contains { $0.message?.contains("Duplicate") == true })
        }
    }

    func testExplicitLinkCannotEscapeSelectedRoot() throws {
        try withFolders { root, source, target in
            let external = root.appendingPathComponent("external.txt")
            try Data("outside\n".utf8).write(to: external)
            let link = source.appendingPathComponent("outside.txt")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)
            let report = try ConversionManager().convertSelections([link], to: target, format: .json)
            XCTAssertEqual(report.convertedCount, 0)
            XCTAssertEqual(report.skippedCount, 1)
            XCTAssertTrue(report.entries[0].message?.contains("Symbolic link") == true)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.path).count, 0)
        }
    }

    func testBinaryPropertyListAndNativeBinarySignaturesStayDispatchable() throws {
        try withFolders { _, source, target in
            let plist = source.appendingPathComponent("binary.plist")
            let payload = try PropertyListSerialization.data(fromPropertyList: ["name": "Skald"], format: .binary, options: 0)
            try payload.write(to: plist)
            let report = try ConversionManager().convertSelections([plist], to: target, format: .json)
            XCTAssertEqual(report.convertedCount, 1)
            let ole = source.appendingPathComponent("document.doc")
            try Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]).write(to: ole)
            let heic = source.appendingPathComponent("photo.heic")
            try Data([0, 0, 0, 12, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63]).write(to: heic)
            if case .compatible = try ContentProbe().inspect(ole, fileExtension: "doc", knownExtension: true) {} else { XCTFail("OLE signature") }
            if case .compatible = try ContentProbe().inspect(heic, fileExtension: "heic", knownExtension: true) {} else { XCTFail("HEIC signature") }
        }
    }
}
