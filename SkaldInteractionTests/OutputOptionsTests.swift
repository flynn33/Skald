import XCTest

final class OutputOptionsTests: XCTestCase {
    func testBothAndBundleControlsAreSelectable() {
        let skald = XCUIApplication(bundleIdentifier: "com.daley.jim.Skald")
        skald.launch()

        let both = skald.radioButtons["Both"]
        XCTAssertTrue(both.waitForExistence(timeout: 15), skald.debugDescription)
        both.click()
        XCTAssertEqual(both.value as? String, "1")

        let bundle = skald.checkBoxes["Bundle original with outputs"]
        XCTAssertTrue(bundle.waitForExistence(timeout: 5), skald.debugDescription)
        bundle.click()
        XCTAssertEqual(bundle.value as? String, "1")
    }
}
