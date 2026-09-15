import Foundation
import ImageIO

nonisolated struct ImageInputError: Error, LocalizedError {
    let code: String
    let summary: String
    var errorDescription: String? { "\(code): \(summary)" }
}

nonisolated final class ImageOCRConverter: DocumentConverter {
    let supportedExtensions = ["png", "jpg", "jpeg", "heic", "tiff", "tif"]
    private let parser = PlainTextParser()
    private let ocr: OCRRecognizing
    private let maximumFrames: Int
    private let maximumSourcePixels: UInt64
    private let maximumThumbnailDimension: Int
    private let maximumInputBytes: Int

    init(ocr: OCRRecognizing = VisionOCRService(), maximumFrames: Int = 64, maximumSourcePixels: UInt64 = 40_000_000, maximumThumbnailDimension: Int = 2_048, maximumInputBytes: Int = 64 * 1_024 * 1_024) {
        self.ocr = ocr
        self.maximumFrames = max(1, maximumFrames)
        self.maximumSourcePixels = max(1, maximumSourcePixels)
        self.maximumThumbnailDimension = max(1, maximumThumbnailDimension)
        self.maximumInputBytes = maximumInputBytes
    }

    func convert(at url: URL, to format: OutputFormat) throws -> String {
        try convertDetailed(at: url, to: format).output
    }

    func convertDetailed(at url: URL, to format: OutputFormat) throws -> ConverterOutcome {
        try BoundedInputReader.preflight(url, maximumBytes: maximumInputBytes)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw ImageInputError(code: "invalidImage", summary: "The image source could not be opened.")
        }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else { throw ImageInputError(code: "invalidImage", summary: "The image has no frames.") }
        guard frameCount <= maximumFrames else { throw ImageInputError(code: "frameLimitExceeded", summary: "The image exceeds the configured frame limit.") }
        var pages: [ReadablePage] = []
        var warnings: [String] = []
        var hasText = false
        var hasPartialFrame = false
        for index in 0..<frameCount {
            if Task.isCancelled { throw OutputPublicationError.cancelled }
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0 else {
                hasPartialFrame = true
                warnings.append("framePropertiesUnavailable")
                pages.append(ReadablePage(page: index + 1, blockCount: 0, blocks: [], extractionSource: "none", status: "partial", warnings: ["framePropertiesUnavailable"]))
                continue
            }
            guard UInt64(width) <= maximumSourcePixels / UInt64(height) else {
                throw ImageInputError(code: "imagePixelLimitExceeded", summary: "An image frame exceeds the configured pixel limit.")
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumThumbnailDimension,
                kCGImageSourceShouldCacheImmediately: false
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else {
                hasPartialFrame = true
                warnings.append("frameDecodeFailed")
                pages.append(ReadablePage(page: index + 1, blockCount: 0, blocks: [], extractionSource: "none", status: "partial", warnings: ["frameDecodeFailed"]))
                continue
            }
            do {
                let recognized = try ocr.recognize(image)
                let blocks = parser.parse(recognized.text)
                hasText = hasText || !blocks.isEmpty
                let ambiguous = recognized.warnings.contains("lowOCRConfidence")
                if ambiguous { hasPartialFrame = true }
                let status = ambiguous ? "partial" : (blocks.isEmpty ? "empty" : "complete")
                pages.append(ReadablePage(page: index + 1, blockCount: blocks.count, blocks: blocks, extractionSource: "visionOCR", status: status, warnings: recognized.warnings.isEmpty ? nil : recognized.warnings, confidence: recognized.confidence))
                warnings.append(contentsOf: recognized.warnings)
            } catch {
                if Task.isCancelled { throw OutputPublicationError.cancelled }
                hasPartialFrame = true
                warnings.append("ocrFailed")
                pages.append(ReadablePage(page: index + 1, blockCount: 0, blocks: [], extractionSource: "visionOCR", status: "partial", warnings: ["ocrFailed"]))
            }
        }
        let quality: ExtractionQuality = hasPartialFrame ? .partial : (hasText ? .complete : .empty)
        let output: String
        switch format {
        case .markdown:
            output = ReadableOutputFormatter.markdownDocument(title: "Image document", extractedPages: pages)
        case .json:
            output = try ReadableOutputFormatter.jsonDocument(fileName: url.lastPathComponent, sourceExtension: SourceFileDescriptor(url: url).fileExtension, extractedPages: pages)
        }
        return ConverterOutcome(output: output, quality: quality, warnings: warnings)
    }
}
