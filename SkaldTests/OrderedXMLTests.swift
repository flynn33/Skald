import Foundation
import XCTest
@testable import Skald

final class OrderedXMLTests: XCTestCase {
    private func fixture(_ name: String) throws -> URL {
        let root = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent("Corpus/xml"))
        return root.appendingPathComponent(name)
    }

    private func rootNode(_ name: String) throws -> [String: Any] {
        let output = try XMLConverter().convert(at: fixture(name), to: .json)
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        XCTAssertEqual(document["version"] as? String, "2.0")
        let content = try XCTUnwrap(document["content"] as? [String: Any])
        let data = try XCTUnwrap(content["data"] as? [String: Any])
        return try XCTUnwrap(data["$xml"] as? [String: Any])
    }

    func testMixedTextChildTextOrder() throws {
        let node = try rootNode("mixed-content.xml")
        XCTAssertEqual(node["name"] as? String, "p")
        let content = try XCTUnwrap(node["content"] as? [[String: Any]])
        XCTAssertEqual(content.compactMap { $0["kind"] as? String }, ["text", "element", "text"])
        XCTAssertEqual(content[0]["text"] as? String, "Hello ")
        let bold = try XCTUnwrap(content[1]["element"] as? [String: Any])
        XCTAssertEqual(bold["name"] as? String, "b")
        XCTAssertEqual((bold["content"] as? [[String: Any]])?.first?["text"] as? String, "world")
        XCTAssertEqual(content[2]["text"] as? String, "!")
    }

    func testInterleavedSiblingNamesKeepSourceOrder() throws {
        let node = try rootNode("ordered-siblings.xml")
        let content = try XCTUnwrap(node["content"] as? [[String: Any]])
        XCTAssertEqual(content.compactMap { ($0["element"] as? [String: Any])?["name"] as? String }, ["a", "b", "a"])
        XCTAssertEqual(content.compactMap { (($0["element"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String }, ["first", "middle", "last"])
    }

    func testXMLSpacePreservesBeforeAndAfterWhitespace() throws {
        let node = try rootNode("preserved-space.xml")
        let attributes = try XCTUnwrap(node["attributes"] as? [[String: Any]])
        XCTAssertTrue(attributes.contains { ($0["name"] as? String) == "xml:space" && ($0["value"] as? String) == "preserve" })
        let content = try XCTUnwrap(node["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["text"] as? String, "  ")
        XCTAssertEqual(content.last?["text"] as? String, "  ")
    }

    func testMalformedAndDTDInputsFailWithoutNormalOutput() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Skald-XML-Negative-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (name, text, code) in [
            ("broken.xml", "<root><child></root>", "malformedXML"),
            ("entity.xml", "<!DOCTYPE root [<!ENTITY secret SYSTEM \"file:///tmp/secret\">]><root>&secret;</root>", "externalEntityDenied")
        ] {
            let file = root.appendingPathComponent(name)
            try Data(text.utf8).write(to: file)
            XCTAssertThrowsError(try XMLConverter().convert(at: file, to: .json)) { error in
                XCTAssertEqual((error as? XMLInputError)?.code, code)
            }
        }
        let dtd = "<?xml version=\"1.0\" encoding=\"UTF-16\"?><!DOCTYPE root [<!ENTITY secret \"expanded\">]><root>&secret;</root>"
        let encoded = root.appendingPathComponent("entity-utf16.xml")
        try XCTUnwrap(dtd.data(using: .utf16)).write(to: encoded)
        XCTAssertThrowsError(try XMLConverter().convert(at: encoded, to: .json)) { error in
            XCTAssertEqual((error as? XMLInputError)?.code, "externalEntityDenied")
        }
    }

    func testNamespaceIdentityAndCDATAStaySeparateFromChildOrder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Skald-XML-Namespace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("namespaced.xml")
        try Data("<root xmlns:p=\"urn:test\"><p:item p:attr=\"x\">left<![CDATA[<literal>]]>right</p:item></root>".utf8).write(to: file)
        let output = try XMLConverter().convert(at: file, to: .json)
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        let content = try XCTUnwrap(document["content"] as? [String: Any])
        let data = try XCTUnwrap(content["data"] as? [String: Any])
        let rootNode = try XCTUnwrap(data["$xml"] as? [String: Any])
        let child = try XCTUnwrap((rootNode["content"] as? [[String: Any]])?.first?["element"] as? [String: Any])
        XCTAssertEqual(child["namespaceURI"] as? String, "urn:test")
        XCTAssertEqual(child["name"] as? String, "p:item")
        let attributes = try XCTUnwrap(child["attributes"] as? [[String: Any]])
        XCTAssertTrue(attributes.contains { $0["name"] as? String == "p:attr" && $0["namespaceURI"] as? String == "urn:test" && $0["value"] as? String == "x" })
        let segments = try XCTUnwrap(child["content"] as? [[String: Any]])
        XCTAssertEqual(segments.compactMap { $0["kind"] as? String }, ["text", "cdata", "text"])
        XCTAssertEqual(segments.compactMap { $0["text"] as? String }, ["left", "<literal>", "right"])
    }

    func testConfiguredNodeDepthAndTextLimitsAreControlled() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Skald-XML-Limits-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (name, text, converter, code) in [
            ("nodes.xml", "<a><b/><c/></a>", XMLConverter(maximumNodes: 2), "nodeLimitExceeded"),
            ("depth.xml", "<a><b/></a>", XMLConverter(maximumDepth: 1), "depthLimitExceeded"),
            ("text.xml", "<a>long</a>", XMLConverter(maximumTextBytes: 2), "textLimitExceeded")
        ] {
            let file = root.appendingPathComponent(name)
            try Data(text.utf8).write(to: file)
            XCTAssertThrowsError(try converter.convert(at: file, to: .json)) { error in
                XCTAssertEqual((error as? XMLInputError)?.code, code)
            }
        }
    }
}
