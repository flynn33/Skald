import AppKit
import CoreGraphics
import CoreText
import Foundation
import PDFKit
import XCTest
@testable import Skald

private final class FixedPDFOCR: OCRRecognizing {
    let result: OCRTextResult
    private(set) var calls = 0
    init(_ text: String) { result = OCRTextResult(text: text, confidence: 0.8, warnings: text.isEmpty ? ["noTextRecognized"] : []) }
    func recognize(_ image: CGImage) throws -> OCRTextResult { calls += 1; return result }
}

private final class FailingPDFOCR: OCRRecognizing {
    func recognize(_ image: CGImage) throws -> OCRTextResult { throw NSError(domain: "PDFOCRTest", code: 1) }
}

final class PDFExtractionTests: XCTestCase {
    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Skald-PDF-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private func makePDF(_ url: URL, pageTexts: [String?]) throws {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        for text in pageTexts {
            context.beginPDFPage(nil)
            if let text {
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 24)]))
                context.textPosition = CGPoint(x: 72, y: 700)
                CTLineDraw(line, context)
            }
            context.endPDFPage()
        }
        context.closePDF()
    }

    private func makeScannedPDF(_ url: URL) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmap = try XCTUnwrap(CGContext(data: nil, width: 1000, height: 400, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        bitmap.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: 1000, height: 400))
        bitmap.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "WOLF", attributes: [.font: NSFont.systemFont(ofSize: 140)]))
        bitmap.textPosition = CGPoint(x: 90, y: 140)
        CTLineDraw(line, bitmap)
        let image = try XCTUnwrap(bitmap.makeImage())
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let pdf = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        pdf.beginPDFPage(nil)
        pdf.draw(image, in: CGRect(x: 50, y: 430, width: 500, height: 200))
        pdf.endPDFPage()
        pdf.closePDF()
    }

    func testProductionVisionReadsRasterOnlyPDF() throws {
        try withDirectory { root in
            let file = root.appendingPathComponent("scanned.pdf")
            try makeScannedPDF(file)
            XCTAssertTrue((PDFDocument(url: file)?.page(at: 0)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            let result = try PDFConverter().convertDetailed(at: file, to: .json)
            XCTAssertTrue(result.output.uppercased().contains("WOLF"), result.output)
            XCTAssertTrue(result.output.contains("visionOCR"))
        }
    }

    func testNativeAndOCRPagesKeepIdentityWithoutDuplicatingNativeText() throws {
        try withDirectory { root in
            let file = root.appendingPathComponent("mixed.pdf")
            try makePDF(file, pageTexts: ["NATIVE SIGNAL", nil])
            let ocr = FixedPDFOCR("SCANNED WOLF")
            let converter = PDFConverter(ocr: ocr)
            let result = try converter.convertDetailed(at: file, to: .json)
            XCTAssertEqual(result.quality, .complete)
            XCTAssertEqual(ocr.calls, 1)
            let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any])
            XCTAssertEqual(document["version"] as? String, "2.0")
            let content = try XCTUnwrap(document["content"] as? [String: Any])
            let pages = try XCTUnwrap(content["pages"] as? [[String: Any]])
            XCTAssertEqual(pages.compactMap { $0["page"] as? Int }, [1, 2])
            XCTAssertEqual(pages.compactMap { $0["extractionSource"] as? String }, ["native", "visionOCR"])
            XCTAssertTrue((pages[0]["blocks"] as? [[String: Any]])?.contains { ($0["text"] as? String)?.contains("NATIVE SIGNAL") == true } == true)
            XCTAssertTrue((pages[1]["blocks"] as? [[String: Any]])?.contains { ($0["text"] as? String)?.contains("SCANNED WOLF") == true } == true)
            XCTAssertFalse((pages[1]["blocks"] as? [[String: Any]])?.contains { ($0["text"] as? String)?.contains("NATIVE SIGNAL") == true } == true)
        }
    }

    func testRepeatedMeaningfulNativeTextIsNotStripped() throws {
        try withDirectory { root in
            let file = root.appendingPathComponent("repeated.pdf")
            try makePDF(file, pageTexts: ["PRESERVE ME", "PRESERVE ME"])
            let result = try PDFConverter(ocr: FixedPDFOCR("unused")).convertDetailed(at: file, to: .json)
            XCTAssertEqual(result.quality, .complete)
            XCTAssertEqual(result.output.components(separatedBy: "PRESERVE ME").count - 1, 2)
        }
    }

    func testLockedPDFRequiresPasswordAndPublishesNoNormalArtifact() throws {
        try withDirectory { root in
            let plain = root.appendingPathComponent("plain.pdf")
            let locked = root.appendingPathComponent("locked.pdf")
            try makePDF(plain, pageTexts: ["TOP SECRET"])
            let source = try XCTUnwrap(PDFDocument(url: plain))
            XCTAssertTrue(source.write(to: locked, withOptions: [.ownerPasswordOption: "owner", .userPasswordOption: "viewer"]))
            XCTAssertTrue(try XCTUnwrap(PDFDocument(url: locked)).isLocked)
            XCTAssertThrowsError(try PDFConverter().convert(at: locked, to: .json)) { error in
                XCTAssertEqual((error as? PDFExtractionError)?.code, "passwordRequired")
            }
        }
    }

    func testNoTextAndOCRFailureAreDistinctOutcomes() throws {
        try withDirectory { root in
            let file = root.appendingPathComponent("blank.pdf")
            try makePDF(file, pageTexts: [nil])
            let empty = try PDFConverter(ocr: FixedPDFOCR("")).convertDetailed(at: file, to: .json)
            XCTAssertEqual(empty.quality, .empty)
            XCTAssertTrue(empty.output.contains("noTextRecognized"))
            let partial = try PDFConverter(ocr: FailingPDFOCR()).convertDetailed(at: file, to: .json)
            XCTAssertEqual(partial.quality, .partial)
            XCTAssertTrue(partial.output.contains("ocrFailed"))
        }
    }

    func testPageLimitFailsBeforeRasterization() throws {
        try withDirectory { root in
            let file = root.appendingPathComponent("two.pdf")
            try makePDF(file, pageTexts: [nil, nil])
            XCTAssertThrowsError(try PDFConverter(ocr: FixedPDFOCR("unused"), maximumPages: 1).convert(at: file, to: .json)) { error in
                XCTAssertEqual((error as? PDFExtractionError)?.code, "pageLimitExceeded")
            }
        }
    }
}
