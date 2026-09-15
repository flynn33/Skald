import Darwin
import Foundation
import XCTest
@testable import Skald

nonisolated struct OutsideTargetPlanner: OutputFilePlanning {
    func planOutput(for sourceURL: URL, in targetDirectoryURL: URL, outputExtension: String, reservedOutputPaths: Set<String>) throws -> OutputFilePlan {
        OutputFilePlan(url: targetDirectoryURL.deletingLastPathComponent().appendingPathComponent("outside.md"), wasRenamed: false)
    }
}

final class OutputWriterRegressionTests: XCTestCase {
    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Skald-Writer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    func testOccupiedTargetAndSourceRemainUnchanged() throws {
        try withDirectory { root in
            let source = root.appendingPathComponent("records.csv")
            let existing = root.appendingPathComponent("records.md")
            let sourceBytes = Data("source bytes".utf8)
            let existingBytes = Data("existing bytes".utf8)
            try sourceBytes.write(to: source)
            try existingBytes.write(to: existing)
            let result = try OutputWriter().publish(Data("complete output".utf8), for: source, in: root, outputExtension: "md", reservedOutputPaths: [])
            XCTAssertEqual(result.url.lastPathComponent, "records-csv.md")
            XCTAssertEqual(try Data(contentsOf: source), sourceBytes)
            XCTAssertEqual(try Data(contentsOf: existing), existingBytes)
            XCTAssertEqual(try Data(contentsOf: result.url), Data("complete output".utf8))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 3)
        }
    }

    func testDanglingSymlinkDestinationIsNeverReplaced() throws {
        try withDirectory { root in
            let source = root.appendingPathComponent("records.csv")
            try Data("source".utf8).write(to: source)
            let destination = root.appendingPathComponent("records.md")
            let missing = root.appendingPathComponent("missing.md")
            XCTAssertEqual(symlink(missing.path, destination.path), 0)
            let result = try OutputWriter().publish(Data("output".utf8), for: source, in: root, outputExtension: "md", reservedOutputPaths: [])
            XCTAssertEqual(result.url.lastPathComponent, "records-csv.md")
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: destination.path), missing.path)
            XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        }
    }

    func testConcurrentPublishersChooseDistinctFinalNames() throws {
        try withDirectory { root in
            let source = root.appendingPathComponent("records.csv")
            try Data("source".utf8).write(to: source)
            let lock = NSLock()
            var results: [URL] = []
            var failures: [Error] = []
            let group = DispatchGroup()
            for index in 0..<12 {
                group.enter()
                DispatchQueue.global().async {
                    defer { group.leave() }
                    do {
                        let data = Data("payload-\(index)".utf8)
                        let result = try OutputWriter().publish(data, for: source, in: root, outputExtension: "md", reservedOutputPaths: [])
                        lock.lock(); results.append(result.url); lock.unlock()
                    } catch {
                        lock.lock(); failures.append(error); lock.unlock()
                    }
                }
            }
            XCTAssertEqual(group.wait(timeout: .now() + 30), .success)
            XCTAssertTrue(failures.isEmpty, "All publishers must either commit or report a controlled error: \(failures)")
            XCTAssertEqual(Set(results).count, 12)
            XCTAssertEqual(try Data(contentsOf: source), Data("source".utf8))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 13)
        }
    }

    func testInjectedShortWriteAndEINTRCompletePayload() throws {
        try withDirectory { root in
            let source = root.appendingPathComponent("records.csv")
            try Data("source".utf8).write(to: source)
            var calls = 0
            let writer = OutputWriter(writeCall: { fd, pointer, length in
                calls += 1
                if calls == 1 { errno = EINTR; return -1 }
                return Darwin.write(fd, pointer, min(length, 3))
            })
            let payload = Data("abcdefghijklmnopqrstuvwxyz".utf8)
            let result = try writer.publish(payload, for: source, in: root, outputExtension: "md", reservedOutputPaths: [])
            XCTAssertEqual(try Data(contentsOf: result.url), payload)
            XCTAssertGreaterThan(calls, 2)
        }
    }

    func testWriteFailureAndCancellationLeaveNoFinalOrTemporaryFiles() throws {
        try withDirectory { root in
            let source = root.appendingPathComponent("records.csv")
            try Data("source".utf8).write(to: source)
            let failed = OutputWriter(writeCall: { _, _, _ in errno = ENOSPC; return -1 })
            XCTAssertThrowsError(try failed.publish(Data("payload".utf8), for: source, in: root, outputExtension: "md", reservedOutputPaths: []))
            let cancelled = OutputWriter(isCancelled: { true })
            XCTAssertThrowsError(try cancelled.publish(Data("payload".utf8), for: source, in: root, outputExtension: "md", reservedOutputPaths: []))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 1)
        }
    }

    func testUnsupportedExclusiveRenameReturnsCapabilityError() throws {
        try withDirectory { root in
            let source = root.appendingPathComponent("records.csv")
            try Data("source".utf8).write(to: source)
            let writer = OutputWriter(supportsExclusiveRenaming: { _ in false })
            XCTAssertThrowsError(try writer.publish(Data("payload".utf8), for: source, in: root, outputExtension: "md", reservedOutputPaths: [])) { error in
                guard case OutputPublicationError.exclusiveRenameUnsupported = error else { return XCTFail("Unexpected error: \(error)") }
            }
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 1)
        }
    }
    func testOccupiedSymlinkAndTargetDataRemainUnchanged() throws {
        try withDirectory { root in
            let source = root.appendingPathComponent("records.csv")
            let sentinel = root.appendingPathComponent("sentinel.md")
            let destination = root.appendingPathComponent("records.md")
            try Data("source".utf8).write(to: source)
            let sentinelBytes = Data("sentinel".utf8)
            try sentinelBytes.write(to: sentinel)
            XCTAssertEqual(symlink(sentinel.path, destination.path), 0)
            let result = try OutputWriter().publish(Data("new".utf8), for: source, in: root, outputExtension: "md", reservedOutputPaths: [])
            XCTAssertEqual(result.url.lastPathComponent, "records-csv.md")
            XCTAssertEqual(try Data(contentsOf: sentinel), sentinelBytes)
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: destination.path), sentinel.path)
        }
    }

    func testCollisionLimitDoesNotRemoveCompetingDestination() throws {
        try withDirectory { root in
            let source = root.appendingPathComponent("records.csv")
            try Data("source".utf8).write(to: source)
            var inserted = false
            let competitor = Data("competitor".utf8)
            let writer = OutputWriter(collisionLimit: 1, beforeExclusiveRename: { destination in
                if !inserted { try? competitor.write(to: destination); inserted = true }
            })
            XCTAssertThrowsError(try writer.publish(Data("new".utf8), for: source, in: root, outputExtension: "md", reservedOutputPaths: [])) { error in
                guard case OutputPublicationError.collisionLimit = error else { return XCTFail("Unexpected error: \(error)") }
            }
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("records.md")), competitor)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 2)
        }
    }

    func testCancellationAfterCommitPreservesPublishedArtifact() throws {
        try withDirectory { root in
            let source = root.appendingPathComponent("records.csv")
            try Data("source".utf8).write(to: source)
            var cancelled = false
            let writer = OutputWriter(renameCall: { directoryFD, oldName, newName in
                let result = oldName.withCString { old in
                    newName.withCString { new in renameatx_np(directoryFD, old, directoryFD, new, UInt32(RENAME_EXCL)) }
                }
                if result == 0 { cancelled = true }
                return result
            }, isCancelled: { cancelled })
            let result = try writer.publish(Data("complete".utf8), for: source, in: root, outputExtension: "md", reservedOutputPaths: [])
            XCTAssertTrue(cancelled)
            XCTAssertEqual(try Data(contentsOf: result.url), Data("complete".utf8))
        }
    }

    func testCancellationDuringWriteCleansOwnedTemporaryFile() throws {
        try withDirectory { root in
            let source = root.appendingPathComponent("records.csv")
            try Data("source".utf8).write(to: source)
            var cancelled = false
            let writer = OutputWriter(writeCall: { fd, pointer, length in
                let count = Darwin.write(fd, pointer, min(length, 2))
                cancelled = true
                return count
            }, isCancelled: { cancelled })
            XCTAssertThrowsError(try writer.publish(Data("long payload".utf8), for: source, in: root, outputExtension: "md", reservedOutputPaths: [])) { error in
                guard case OutputPublicationError.cancelled = error else { return XCTFail("Unexpected error: \(error)") }
            }
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 1)
        }
    }

    func testChangedTargetDirectoryIsRejectedBeforeCommit() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("Skald-Target-Race-\(UUID().uuidString)", isDirectory: true)
        let target = parent.appendingPathComponent("target", isDirectory: true)
        let moved = parent.appendingPathComponent("moved", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let source = target.appendingPathComponent("records.csv")
        try Data("source".utf8).write(to: source)
        var movedOnce = false
        let writer = OutputWriter(beforeExclusiveRename: { _ in
            if !movedOnce {
                try? FileManager.default.moveItem(at: target, to: moved)
                try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
                movedOnce = true
            }
        })
        XCTAssertThrowsError(try writer.publish(Data("new".utf8), for: source, in: target, outputExtension: "md", reservedOutputPaths: [])) { error in
            guard case OutputPublicationError.targetChanged = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(try Data(contentsOf: moved.appendingPathComponent("records.csv")), Data("source".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: moved.path).count, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.path).count, 0)
    }

    func testDirectoryWithoutWritePermissionDoesNotPublish() throws {
        try withDirectory { root in
            let source = root.appendingPathComponent("records.csv")
            try Data("source".utf8).write(to: source)
            XCTAssertEqual(chmod(root.path, 0o500), 0)
            defer { _ = chmod(root.path, 0o700) }
            XCTAssertThrowsError(try OutputWriter().publish(Data("new".utf8), for: source, in: root, outputExtension: "md", reservedOutputPaths: []))
            XCTAssertEqual(try Data(contentsOf: source), Data("source".utf8))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 1)
        }
    }
    func testInjectedPlannerCannotPublishOutsideSelectedDirectory() throws {
        try withDirectory { root in
            let source = root.appendingPathComponent("records.csv")
            try Data("source".utf8).write(to: source)
            let writer = OutputWriter(planner: OutsideTargetPlanner())
            XCTAssertThrowsError(try writer.publish(Data("new".utf8), for: source, in: root, outputExtension: "md", reservedOutputPaths: [])) { error in
                guard case OutputPublicationError.invalidCandidate = error else { return XCTFail("Unexpected error: \(error)") }
            }
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 1)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.deletingLastPathComponent().appendingPathComponent("outside.md").path))
        }
    }
}
