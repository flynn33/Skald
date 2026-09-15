import CoreGraphics
import Foundation
import Vision

nonisolated struct OCRTextResult {
    let text: String
    let confidence: Double?
    let warnings: [String]
}

nonisolated protocol OCRRecognizing {
    func recognize(_ image: CGImage) throws -> OCRTextResult
}

nonisolated final class VisionOCRService: OCRRecognizing {
    private let languages: [String]
    init(languages: [String] = []) { self.languages = languages }

    func recognize(_ image: CGImage) throws -> OCRTextResult {
        if Task.isCancelled { throw OutputPublicationError.cancelled }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if !languages.isEmpty { request.recognitionLanguages = languages }
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        if Task.isCancelled { throw OutputPublicationError.cancelled }
        let candidates = (request.results ?? []).compactMap { $0.topCandidates(1).first }
        let text = candidates.map(\.string).joined(separator: "\n")
        let confidence = candidates.isEmpty ? nil : candidates.map { Double($0.confidence) }.reduce(0, +) / Double(candidates.count)
        var warnings = candidates.isEmpty ? ["noTextRecognized"] : []
        if let confidence, confidence < 0.6 { warnings.append("lowOCRConfidence") }
        return OCRTextResult(text: text, confidence: confidence, warnings: warnings)
    }
}
