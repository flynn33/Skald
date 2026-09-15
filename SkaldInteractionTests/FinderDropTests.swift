import Foundation
import XCTest

final class FinderDropTests: XCTestCase {
    func testFinderDropSelectsTwoFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Skald-FinderDrop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "name,age\nAda,37\n".write(to: folder.appendingPathComponent("a.csv"), atomically: true, encoding: .utf8)
        try "Drop source\n".write(to: folder.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: folder) }

        let skald = XCUIApplication(bundleIdentifier: "com.daley.jim.Skald")
        skald.launch()
        XCTAssertTrue(skald.buttons["Choose"].firstMatch.waitForExistence(timeout: 15))

        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        finder.typeKey("g", modifierFlags: [.command, .shift])
        finder.typeText(folder.path)
        finder.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        XCTAssertTrue(finder.images["a.csv"].waitForExistence(timeout: 15), finder.debugDescription)
        XCTAssertTrue(finder.images["b.txt"].exists)

        finder.images["a.csv"].click()
        finder.typeKey("a", modifierFlags: .command)
        let source = finder.images["a.csv"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let destination = skald.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: 210, dy: 145))
        XCTContext.runActivity(named: "Finder to Skald drop") { activity in
            activity.add(XCTAttachment(string: "Finder: \(finder.windows.firstMatch.frame) Skald: \(skald.windows.firstMatch.frame) drop: \(destination.screenPoint)"))
            source.press(forDuration: 1, thenDragTo: destination)
        }
        skald.activate()
        XCTAssertTrue(skald.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "2 selected")).firstMatch.waitForExistence(timeout: 15), skald.debugDescription)
    }
}
