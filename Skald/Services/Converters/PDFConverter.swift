import AppKit
import Foundation
import PDFKit

nonisolated struct PDFExtractionError: Error, LocalizedError {
    let code: String
    let summary: String
    var errorDescription: String? { "\(code): \(summary)" }
}

nonisolated final class PDFConverter: DocumentConverter {
    let supportedExtensions = ["pdf"]
    private let parser = PDFTextParser()
    private let plainParser = PlainTextParser()
    private let ocr: OCRRecognizing
    private let maximumPages: Int
    private let maximumRasterPixels: Int
    private let maximumRasterDimension: Int
    private let maximumInputBytes: Int

    init(ocr: OCRRecognizing = VisionOCRService(), maximumPages: Int = 64, maximumRasterPixels: Int = 4_000_000, maximumRasterDimension: Int = 2_048, maximumInputBytes: Int = 64 * 1_024 * 1_024) {
        self.ocr = ocr
        self.maximumPages = max(1, maximumPages)
        self.maximumRasterPixels = max(1, maximumRasterPixels)
        self.maximumRasterDimension = max(1, maximumRasterDimension)
        self.maximumInputBytes = maximumInputBytes
    }

    func convert(at url: URL, to format: OutputFormat) throws -> String {
        try convertDetailed(at: url, to: format).output
    }

    func convertDetailed(at url: URL, to format: OutputFormat) throws -> ConverterOutcome {
        try BoundedInputReader.preflight(url, maximumBytes: maximumInputBytes)
        guard let document = PDFDocument(url: url) else {
            throw PDFExtractionError(code: "invalidPDF", summary: "The PDF could not be opened.")
        }
        guard !document.isLocked else {
            throw PDFExtractionError(code: "passwordRequired", summary: "The PDF is locked and requires a password.")
        }
        guard document.pageCount <= maximumPages else {
            throw PDFExtractionError(code: "pageLimitExceeded", summary: "The PDF exceeds the configured page limit.")
        }
        let nativePages = parser.parsePages(from: document)
        var pages: [ReadablePage] = []
        var warnings: [String] = []
        var hasPartialPage = false
        var hasAnyText = false

        for index in 0..<document.pageCount {
            if Task.isCancelled { throw OutputPublicationError.cancelled }
            guard let page = document.page(at: index) else {
                hasPartialPage = true
                warnings.append("pageUnavailable")
                pages.append(ReadablePage(page: index + 1, blockCount: 0, blocks: [], extractionSource: "none", status: "partial", warnings: ["pageUnavailable"]))
                continue
            }
            let nativeText = page.string ?? ""
            if usableNativeText(nativeText) {
                let parsed = index < nativePages.count ? nativePages[index] : []
                let blocks = parsed.isEmpty ? plainParser.parse(nativeText) : parsed
                hasAnyText = hasAnyText || !blocks.isEmpty
                pages.append(ReadablePage(page: index + 1, blockCount: blocks.count, blocks: blocks, extractionSource: "native", status: "complete"))
                continue
            }
            guard let image = rasterImage(page) else {
                hasPartialPage = true
                warnings.append("pageRasterizationFailed")
                pages.append(ReadablePage(page: index + 1, blockCount: 0, blocks: [], extractionSource: "none", status: "partial", warnings: ["pageRasterizationFailed"]))
                continue
            }
            do {
                let recognized = try ocr.recognize(image)
                let blocks = plainParser.parse(recognized.text)
                let ambiguous = recognized.warnings.contains("lowOCRConfidence")
                if ambiguous { hasPartialPage = true }
                let status = ambiguous ? "partial" : (blocks.isEmpty ? "empty" : "complete")
                hasAnyText = hasAnyText || !blocks.isEmpty
                pages.append(ReadablePage(page: index + 1, blockCount: blocks.count, blocks: blocks, extractionSource: "visionOCR", status: status, warnings: recognized.warnings.isEmpty ? nil : recognized.warnings, confidence: recognized.confidence))
                warnings.append(contentsOf: recognized.warnings)
            } catch {
                if Task.isCancelled { throw OutputPublicationError.cancelled }
                hasPartialPage = true
                warnings.append("ocrFailed")
                pages.append(ReadablePage(page: index + 1, blockCount: 0, blocks: [], extractionSource: "visionOCR", status: "partial", warnings: ["ocrFailed"]))
            }
        }
        let quality: ExtractionQuality = hasPartialPage ? .partial : (hasAnyText ? .complete : .empty)
        let output: String
        switch format {
        case .markdown:
            output = ReadableOutputFormatter.markdownDocument(title: "PDF document", extractedPages: pages)
        case .json:
            output = try ReadableOutputFormatter.jsonDocument(fileName: url.lastPathComponent, sourceExtension: "pdf", extractedPages: pages)
        }
        return ConverterOutcome(output: output, quality: quality, warnings: warnings)
    }

    private func usableNativeText(_ text: String) -> Bool {
        let visible = text.unicodeScalars.filter { !$0.properties.isWhitespace }
        guard !visible.isEmpty else { return false }
        let unusable = visible.filter { scalar in
            scalar.value == 0xFFFD || (scalar.value < 0x20 && scalar.value != 0x09)
        }
        return unusable.count * 5 < visible.count
    }

    private func rasterImage(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .cropBox)
        guard bounds.width > 0, bounds.height > 0, bounds.width.isFinite, bounds.height.isFinite else { return nil }
        let width = Double(bounds.width)
        let height = Double(bounds.height)
        let scale = min(2.0, Double(maximumRasterDimension) / width, Double(maximumRasterDimension) / height, sqrt(Double(maximumRasterPixels) / (width * height)))
        guard scale > 0 else { return nil }
        let size = CGSize(width: max(1, floor(width * scale)), height: max(1, floor(height * scale)))
        let image = page.thumbnail(of: size, for: .cropBox)
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
