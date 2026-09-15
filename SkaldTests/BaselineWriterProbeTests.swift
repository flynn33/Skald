import Foundation
import XCTest

final class BaselineWriterProbeTests: XCTestCase {
    func testInvalidFlagCombinationTerminatesOnlyChildProcess() throws {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("Skald-Writer-Probe-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: destination) }

        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        child.arguments = ["-e", "import Foundation; try Data(\"probe\".utf8).write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: [.atomic, .withoutOverwriting])", destination.path]
        child.standardOutput = Pipe()
        child.standardError = Pipe()
        try child.run()
        let timeout = DispatchWorkItem { if child.isRunning { child.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeout)
        child.waitUntilExit()
        timeout.cancel()

        XCTAssertNotEqual(child.terminationStatus, 0, "The invalid production flag pair must be reproduced in an isolated process.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }
}
