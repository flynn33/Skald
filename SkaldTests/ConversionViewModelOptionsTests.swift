import Foundation
import XCTest
@testable import Skald

@MainActor
private final class FixedFolderSelector: FolderSelecting {
    private let folders: [URL]
    private var index = 0
    init(_ folders: [URL]) { self.folders = folders }
    func selectFolder() -> URL? {
        defer { index += 1 }
        return index < folders.count ? folders[index] : nil
    }
}

@MainActor
final class ConversionViewModelOptionsTests: XCTestCase {
    func testVisibleInterpretationChoicesReachProductionManagerAndOutput() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Skald-View-Options-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let target = root.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0x61, 0x3B, 0x62, 0x0A, 0x31, 0x3B, 0x93, 0x78, 0x94, 0x0A])
            .write(to: source.appendingPathComponent("records.csv"))

        let viewModel = ConversionViewModel(conversionManager: ConversionManager(), folderSelectionService: FixedFolderSelector([source, target]))
        viewModel.selectSourceFolder()
        viewModel.selectTargetFolder()
        viewModel.outputFormat = .json
        viewModel.textEncoding = .windows1252
        viewModel.delimiterChoice = .semicolon
        viewModel.headerMode = .absent
        XCTAssertTrue(viewModel.canConvert)
        viewModel.convertFiles()
        for _ in 0..<100 {
            if viewModel.report != nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(viewModel.report?.convertedCount, 1)
        XCTAssertEqual(viewModel.report?.failedCount, 0)
        let output = try Data(contentsOf: target.appendingPathComponent("records.json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: output) as? [String: Any])
        let sourceMetadata = try XCTUnwrap(object["source"] as? [String: Any])
        let settings = try XCTUnwrap(sourceMetadata["importSettings"] as? [String: Any])
        XCTAssertEqual(settings["encoding"] as? String, "windows-1252")
        XCTAssertEqual(settings["delimiter"] as? String, ";")
        XCTAssertEqual(settings["headerMode"] as? String, "absent")
        let content = try XCTUnwrap(object["content"] as? [String: Any])
        let table = try XCTUnwrap((content["tables"] as? [[String: Any]])?.first)
        XCTAssertEqual(table["rows"] as? [[String]], [["a", "b"], ["1", "“x”"]])
    }
}
