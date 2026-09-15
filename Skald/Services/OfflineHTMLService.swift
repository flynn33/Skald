import Foundation

nonisolated final class OfflineHTMLService {
    private let tagPattern = try! NSRegularExpression(pattern: "<[^>]*>")
    private let entityPattern = try! NSRegularExpression(pattern: "&(#x[0-9A-Fa-f]+|#[0-9]+|[A-Za-z]+);")
    private let breaks = Set(["p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "br", "li", "blockquote", "pre", "tr", "table", "ul", "ol"])

    func loadText(_ html: String, timeout: TimeInterval) throws -> String {
        guard !Thread.isMainThread else {
            throw AttributedInputError(code: "htmlRequiresBackground", summary: "HTML extraction must run off the main thread.")
        }
        let deadline = Date().addingTimeInterval(timeout)
        let matches = tagPattern.matches(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html))
        var output = ""
        output.reserveCapacity(min(html.utf8.count, 1_024 * 1_024))
        var cursor = html.startIndex
        var ignoredDepth = 0
        for match in matches {
            if Task.isCancelled { throw OutputPublicationError.cancelled }
            if Date() > deadline {
                throw AttributedInputError(code: "htmlImportTimedOut", summary: "HTML extraction exceeded its configured timeout.")
            }
            guard let range = Range(match.range, in: html) else { continue }
            if ignoredDepth == 0 { output += decodeEntities(String(html[cursor..<range.lowerBound])) }
            let token = html[range].dropFirst().dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
            let closing = token.hasPrefix("/")
            let name = String((closing ? token.dropFirst() : Substring(token)).dropLast(token.hasSuffix("/") ? 1 : 0)).lowercased()
            if name == "head" || name == "title" {
                ignoredDepth += closing ? -1 : 1
                ignoredDepth = max(0, ignoredDepth)
            } else if ignoredDepth == 0 && breaks.contains(name) {
                if !output.hasSuffix("\n") { output.append("\n") }
            }
            cursor = range.upperBound
        }
        if ignoredDepth == 0 { output += decodeEntities(String(html[cursor...])) }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodeEntities(_ text: String) -> String {
        let matches = entityPattern.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
        var output = ""
        var cursor = text.startIndex
        let named: [String: String] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " "]
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            output += text[cursor..<range.lowerBound]
            let body = String(text[range].dropFirst().dropLast())
            let replacement: String?
            if body.hasPrefix("#x") {
                replacement = UInt32(body.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map(String.init)
            } else if body.hasPrefix("#") {
                replacement = UInt32(body.dropFirst(), radix: 10).flatMap(Unicode.Scalar.init).map(String.init)
            } else {
                replacement = named[body.lowercased()]
            }
            output += replacement ?? String(text[range])
            cursor = range.upperBound
        }
        output += text[cursor...]
        return output
    }
}
