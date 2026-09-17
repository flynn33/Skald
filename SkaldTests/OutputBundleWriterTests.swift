import Darwin
import Foundation
import XCTest
@testable import Skald

final class OutputBundleWriterTests: XCTestCase {
    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Skald-Bundle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private func outputs() -> [GeneratedOutput] {
        [
            GeneratedOutput(format: .markdown, payload: Data("# Article\n".utf8)),
            GeneratedOutput(format: .json, payload: Data("{\"value\":1}".utf8))
        ]
    }

    func testConcurrentPublishersChooseDistinctCompleteBundles() throws {
        try withDirectory { root in
            let source = root.appendingPathComponent("article.txt")
            try Data("original".utf8).write(to: source)
            let lock = NSLock()
            var results: [URL] = []
            var failures: [Error] = []
            let group = DispatchGroup()
            for _ in 0..<8 {
                group.enter()
                DispatchQueue.global().async {
                    defer { group.leave() }
                    do {
                        let plan = try OutputBundleWriter().publish(self.outputs(), withOriginal: source, in: root,
                                                                    reservedOutputPaths: [])
                        lock.lock(); results.append(plan.url); lock.unlock()
                    } catch {
                        lock.lock(); failures.append(error); lock.unlock()
                    }
                }
            }
            XCTAssertEqual(group.wait(timeout: .now() + 30), .success)
            XCTAssertTrue(failures.isEmpty, "Every publisher must commit a complete distinct bundle: \(failures)")
            XCTAssertEqual(Set(results).count, 8)
            for bundle in results {
                XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: bundle.path)),
                               ["article.txt", "article.md", "article.json"])
            }
            XCTAssertEqual(try Data(contentsOf: source), Data("original".utf8))
        }
    }

    func testRenameFailureCleansOwnedTemporaryBundle() throws {
        try withDirectory { root in
            let source = root.appendingPathComponent("article.txt")
            try Data("original".utf8).write(to: source)
            let writer = OutputBundleWriter(renameCall: { _, _, _ in errno = ENOSPC; return -1 })

            XCTAssertThrowsError(try writer.publish(outputs(), withOriginal: source, in: root, reservedOutputPaths: []))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["article.txt"])
        }
    }

    func testDanglingSymlinkBundleNameIsNeverReplaced() throws {
        try withDirectory { root in
            let source = root.appendingPathComponent("article.txt")
            try Data("original".utf8).write(to: source)
            let occupied = root.appendingPathComponent("article-bundle")
            let missing = root.appendingPathComponent("missing")
            XCTAssertEqual(symlink(missing.path, occupied.path), 0)

            let plan = try OutputBundleWriter().publish(outputs(), withOriginal: source, in: root, reservedOutputPaths: [])

            XCTAssertEqual(plan.url.lastPathComponent, "article-txt-bundle")
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: occupied.path), missing.path)
        }
    }

    func testCancellationAndUnsupportedRenameLeaveNoStagedBundle() throws {
        try withDirectory { root in
            let source = root.appendingPathComponent("article.txt")
            try Data("original".utf8).write(to: source)

            let cancelled = OutputBundleWriter(isCancelled: { true })
            XCTAssertThrowsError(try cancelled.publish(outputs(), withOriginal: source, in: root,
                                                        reservedOutputPaths: [])) { error in
                guard case OutputPublicationError.cancelled = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }

            let unsupported = OutputBundleWriter(supportsExclusiveRenaming: { _ in false })
            XCTAssertThrowsError(try unsupported.publish(outputs(), withOriginal: source, in: root,
                                                          reservedOutputPaths: [])) { error in
                guard case OutputPublicationError.exclusiveRenameUnsupported = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["article.txt"])
        }
    }

    func testChangedTargetDirectoryIsRejectedAndStagingIsRemoved() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("Skald-Bundle-Target-Race-\(UUID().uuidString)", isDirectory: true)
        let target = parent.appendingPathComponent("target", isDirectory: true)
        let moved = parent.appendingPathComponent("moved", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let source = target.appendingPathComponent("article.txt")
        try Data("original".utf8).write(to: source)
        var movedOnce = false
        let writer = OutputBundleWriter(beforeExclusiveRename: { _ in
            if !movedOnce {
                try? FileManager.default.moveItem(at: target, to: moved)
                try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
                movedOnce = true
            }
        })

        XCTAssertThrowsError(try writer.publish(outputs(), withOriginal: source, in: target,
                                                 reservedOutputPaths: [])) { error in
            guard case OutputPublicationError.targetChanged = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: moved.path), ["article.txt"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.path), [])
        XCTAssertEqual(try Data(contentsOf: moved.appendingPathComponent("article.txt")), Data("original".utf8))
    }
}
