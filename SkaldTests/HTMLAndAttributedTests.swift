import AppKit
import Foundation
import Network
import XCTest
@testable import Skald

private nonisolated final class ConnectionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    func read() -> Int { lock.withLock { count } }
}

private nonisolated final class ListenerReadyBox: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    func signal() { semaphore.signal() }
    func wait() -> Bool { semaphore.wait(timeout: .now() + 0.3) == .success }
}

final class HTMLAndAttributedTests: XCTestCase {
    private func withFile(_ name: String, contents: Data, body: (URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Skald-HTML-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent(name)
        try contents.write(to: file)
        try await body(file)
    }

    func testSafeHTMLExtractsOnBackgroundTaskAndTableIsPartial() async throws {
        let html = "<html><body><h1>Skald</h1><p>First line</p><table><tr><td>Cell value</td></tr></table></body></html>"
        try await withFile("sample.html", contents: Data(html.utf8)) { file in
            let outcome = try await Task.detached {
                try AttributedDocumentConverter().convertDetailed(at: file, to: .json)
            }.value
            XCTAssertEqual(outcome.quality, .partial)
            XCTAssertEqual(outcome.warnings, ["tableStructureNotExtracted"])
            XCTAssertTrue(outcome.output.contains("First line"), outcome.output)
            XCTAssertTrue(outcome.output.contains("Cell value"), outcome.output)
        }
    }

    func testResourceBearingHTMLIsDeniedWithoutNetworkRequest() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        let ready = ListenerReadyBox()
        let connections = ConnectionCounter()
        listener.newConnectionHandler = { connection in
            connections.increment()
            connection.cancel()
        }
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
        }
        listener.start(queue: DispatchQueue(label: "SkaldResourceProbe"))
        defer { listener.cancel() }
        // A signed sandbox without a network-server entitlement cannot host
        // this listener. The independent unsandboxed run exercises the live
        // request-count probe; both runs must reject the reference before import.
        let listening = await Task.detached { ready.wait() }.value
        let port = listening ? (listener.port?.rawValue ?? 9) : 9
        let html = "<html><body><img src='http://127.0.0.1:\(port)/pixel'><p>Data</p></body></html>"
        try await withFile("resource.html", contents: Data(html.utf8)) { file in
            do {
                _ = try await Task.detached {
                    try AttributedDocumentConverter().convertDetailed(at: file, to: .json)
                }.value
                XCTFail("Resource-bearing HTML was accepted")
            } catch {
                XCTAssertEqual((error as? AttributedInputError)?.code, "externalResourceDenied")
            }
        }
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(connections.read(), 0, "HTML import made a local network request")
    }

    func testRTFAttachmentAndTableWarningsArePartial() throws {
        let attributed = NSMutableAttributedString(string: "Visible\n", attributes: [.font: NSFont.systemFont(ofSize: 12)])
        let attachment = NSTextAttachment()
        attributed.append(NSAttributedString(attachment: attachment))
        XCTAssertTrue(AttributedDocumentConverter().unextractedFeatures(in: attributed).contains("attachmentNotExtracted"))

        let style = NSMutableParagraphStyle()
        style.textBlocks = [NSTextTableBlock(table: NSTextTable(), startingRow: 0, rowSpan: 1, startingColumn: 0, columnSpan: 1)]
        attributed.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: 7))
        XCTAssertTrue(AttributedDocumentConverter().unextractedFeatures(in: attributed).contains("tableStructureNotExtracted"))
    }

    func testRealRTFAndContainerDocumentsReportTheirLimits() async throws {
        let rtf = try NSAttributedString(string: "Visible RTF paragraph").data(
            from: NSRange(location: 0, length: 21),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        try await withFile("paragraph.rtf", contents: rtf) { file in
            let result = try await Task.detached {
                try AttributedDocumentConverter().convertDetailed(at: file, to: .json)
            }.value
            XCTAssertEqual(result.quality, .complete)
            XCTAssertTrue(result.output.contains("Visible RTF paragraph"), result.output)
        }
        let corpus = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent("Corpus/attributed"))
        for (name, expected) in [("table.docx", "Visible DOCX paragraph"), ("table.odt", "Visible ODT paragraph")] {
            let file = corpus.appendingPathComponent(name)
            let result = try await Task.detached {
                try AttributedDocumentConverter().convertDetailed(at: file, to: .json)
            }.value
            XCTAssertEqual(result.quality, .partial)
            XCTAssertTrue(result.warnings.contains("containerStructuresNotVerified"))
            XCTAssertTrue(result.output.contains(expected), result.output)
        }
    }
}
