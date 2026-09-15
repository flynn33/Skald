import XCTest
@testable import Skald

/// Native regression starters. Adapt only the production API boundary after refactoring.
final class DelimitedParserRegressionTests: XCTestCase {
    private func parse(_ input: String, delimiter: Character = ",") throws -> [[String]] {
        // The baseline is nonthrowing; keep `try` when replacing it with a throwing parser.
        try DelimitedTextParser().parse(input, delimiter: delimiter)
    }

    func testLFControl() throws {
        XCTAssertEqual(try parse("a,b\n1,2\n"), [["a", "b"], ["1", "2"]])
    }

    func testCRControl() throws {
        XCTAssertEqual(try parse("a,b\r1,2\r"), [["a", "b"], ["1", "2"]])
    }

    func testCRLFSeparatesRecords() throws {
        XCTAssertEqual(try parse("a,b\r\n1,2\r\n"), [["a", "b"], ["1", "2"]])
    }

    func testTSVCRLFSeparatesRecords() throws {
        XCTAssertEqual(try parse("a\tb\r\n1\t2\r\n", delimiter: "\t"), [["a", "b"], ["1", "2"]])
    }

    func testQuotedWhitespaceIsData() throws {
        XCTAssertEqual(try parse("a,b\n\"  value  \", tail \n"), [["a", "b"], ["  value  ", " tail "]])
    }

    func testEmptyMultiFieldRecordSurvives() throws {
        XCTAssertEqual(try parse("a,b\n,\n1,2\n"), [["a", "b"], ["", ""], ["1", "2"]])
    }

    func testPhysicallyBlankRecordIsOneEmptyField() throws {
        XCTAssertEqual(try parse("a\n\nz\n"), [["a"], [""], ["z"]])
    }

    func testEmptyInputHasNoRecords() throws {
        XCTAssertEqual(try parse(""), [])
    }

    func testQuotedCRLFPreservedWithinField() throws {
        XCTAssertEqual(try parse("a,b\r\n1,\"left\r\nright\"\r\n"), [["a", "b"], ["1", "left\r\nright"]])
    }

    func testEscapedQuoteAndDelimiter() throws {
        XCTAssertEqual(try parse("a,b\n1,\"comma, and \"\"quote\"\"\"\n"), [["a", "b"], ["1", "comma, and \"quote\""]])
    }

    func testTerminalEmptyField() throws {
        XCTAssertEqual(try parse("a,b,c\nx,y,\n"), [["a", "b", "c"], ["x", "y", ""]])
    }

    func testUnterminatedQuoteIsRejected() {
        XCTAssertThrowsError(try parse("a,b\n1,\"unterminated\n2,value\n"))
    }

    func testQuoteInsideUnquotedFieldIsRejected() {
        XCTAssertThrowsError(try parse("a,b\n1,ab\"cd\n"))
    }

    func testCharactersAfterClosingQuoteAreRejected() {
        XCTAssertThrowsError(try parse("a,b\n1,\"x\"oops\n"))
    }
}
