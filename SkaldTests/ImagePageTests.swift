import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Skald

private final class SequencedImageOCR: OCRRecognizing {
    let texts: [String]
    private(set) var dimensions: [(Int, Int)] = []
    init(_ texts: [String]) { self.texts = texts }
    func recognize(_ image: CGImage) throws -> OCRTextResult {
        dimensions.append((image.width, image.height))
        let text = texts[min(dimensions.count - 1, texts.count - 1)]
        return OCRTextResult(text: text, confidence: 0.9, warnings: text.isEmpty ? ["noTextRecognized"] : [])
    }
}

final class ImagePageTests: XCTestCase {
    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Skald-Image-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private func image(_ text: String? = nil, width: Int = 300, height: Int = 150) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if let text {
            context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 54)]))
            context.textPosition = CGPoint(x: 25, y: 55)
            CTLineDraw(line, context)
        }
        return try XCTUnwrap(context.makeImage())
    }

    private func write(_ images: [CGImage], to url: URL, type: UTType, orientations: [Int] = []) throws {
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, images.count, nil))
        for (index, image) in images.enumerated() {
            let properties: [CFString: Any] = orientations.indices.contains(index) ? [kCGImagePropertyOrientation: orientations[index]] : [:]
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    func testMultipageTIFFKeepsBothFramesAndOrientation() throws {
        try withDirectory { root in
            let file = root.appendingPathComponent("pages.tiff")
            try write([image(width: 200, height: 100), image(width: 200, height: 100)], to: file, type: .tiff, orientations: [1, 6])
            let ocr = SequencedImageOCR(["FIRST FRAME", "SECOND FRAME"])
            let outcome = try ImageOCRConverter(ocr: ocr).convertDetailed(at: file, to: .json)
            XCTAssertEqual(outcome.quality, .complete)
            XCTAssertEqual(ocr.dimensions.count, 2)
            let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(outcome.output.utf8)) as? [String: Any])
            XCTAssertEqual(document["version"] as? String, "2.0")
            let content = try XCTUnwrap(document["content"] as? [String: Any])
            let pages = try XCTUnwrap(content["pages"] as? [[String: Any]])
            XCTAssertEqual(pages.compactMap { $0["page"] as? Int }, [1, 2])
            XCTAssertTrue(outcome.output.contains("FIRST FRAME"))
            XCTAssertTrue(outcome.output.contains("SECOND FRAME"))
            XCTAssertLessThan(ocr.dimensions[1].0, ocr.dimensions[1].1)
        }
    }

    func testEmptyOCRAndFrameLimitAreExplicit() throws {
        try withDirectory { root in
            let file = root.appendingPathComponent("blank.png")
            try write([image()], to: file, type: .png)
            let empty = try ImageOCRConverter(ocr: SequencedImageOCR([""])).convertDetailed(at: file, to: .json)
            XCTAssertEqual(empty.quality, .empty)
            XCTAssertTrue(empty.output.contains("noTextRecognized"))
            let tiff = root.appendingPathComponent("two.tiff")
            try write([image(), image()], to: tiff, type: .tiff)
            XCTAssertThrowsError(try ImageOCRConverter(maximumFrames: 1).convert(at: tiff, to: .json)) { error in
                XCTAssertEqual((error as? ImageInputError)?.code, "frameLimitExceeded")
            }
        }
    }

    func testProductionVisionRecognizesHighContrastTextTolerantly() throws {
        try withDirectory { root in
            let file = root.appendingPathComponent("wolf.png")
            try write([image("WOLF")], to: file, type: .png)
            let result = try ImageOCRConverter().convertDetailed(at: file, to: .json)
            XCTAssertEqual(result.quality, .complete)
            XCTAssertTrue(result.output.uppercased().contains("WOLF"), result.output)
        }
    }
}
