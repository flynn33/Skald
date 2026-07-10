import Foundation
import Vision
import ImageIO

nonisolated final class ImageOCRConverter: DocumentConverter {
    let supportedExtensions = ["png", "jpg", "jpeg", "heic", "tiff", "tif"]
    private let parser = PlainTextParser()

    func convert(at url: URL, to format: OutputFormat) throws -> String {
        guard let cgImage = loadCGImage(from: url) else {
            throw ConversionError.invalidDocument
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []
        let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        let blocks = parser.parse(text)

        switch format {
        case .markdown:
            return ReadableOutputFormatter.markdownDocument(
                title: ReadableOutputFormatter.readableTitle(from: url),
                blocks: blocks
            )
        case .json:
            do {
                return try ReadableOutputFormatter.jsonDocument(
                    fileName: url.lastPathComponent,
                    sourceExtension: SourceFileDescriptor(url: url).fileExtension,
                    blocks: blocks
                )
            } catch {
                throw ConversionError.jsonSerializationFailed
            }
        }
    }

    private func loadCGImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
