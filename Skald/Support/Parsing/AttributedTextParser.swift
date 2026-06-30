import Foundation
import AppKit

nonisolated final class AttributedTextParser {
    private let markdownHeadingRegex = try! NSRegularExpression(pattern: "^(#{1,6})\\s+(.+)$")
    // Recognizes "-"/"*" plus the unambiguous bullet glyphs Word and other
    // editors emit (•, ◦, ▪, ‣), as well as numbered/lettered markers. The
    // middle dot (·) is intentionally excluded — it appears in running text.
    private let listItemRegex = try! NSRegularExpression(pattern: "^\\s*([-*•◦▪‣]|\\d+[.)]|[A-Za-z][.)])\\s+(.+)$")

    func parse(_ attributedString: NSAttributedString) -> [ReadableBlock] {
        let paragraphRanges = self.paragraphRanges(in: attributedString)
        let bodyFontSize = estimateBodyFontSize(for: attributedString, ranges: paragraphRanges)

        var blocks: [ReadableBlock] = []
        var order = 1

        for range in paragraphRanges {
            let paragraphText = attributedString.attributedSubstring(from: range).string
            let trimmed = paragraphText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let heading = parseMarkdownHeading(in: trimmed) {
                blocks.append(
                    ReadableBlock(
                        order: order,
                        type: .heading,
                        text: heading.text,
                        headingLevel: heading.level,
                        listStyle: nil,
                        listDepth: nil,
                        listIndex: nil
                    )
                )
                order += 1
                continue
            }

            let attributes = attributedString.attributes(at: range.location, effectiveRange: nil)
            let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle
            let stats = fontStats(in: range, attributedString: attributedString)

            if let listMatch = listMatch(for: trimmed, paragraphStyle: paragraphStyle) {
                blocks.append(
                    ReadableBlock(
                        order: order,
                        type: .listItem,
                        text: listMatch.text,
                        headingLevel: nil,
                        listStyle: listMatch.style,
                        listDepth: listMatch.depth,
                        listIndex: listMatch.index
                    )
                )
                order += 1
                continue
            }

            if let headingLevel = headingLevel(for: trimmed, fontSize: stats.maxSize, bodyFontSize: bodyFontSize, isBold: stats.isBold) {
                blocks.append(
                    ReadableBlock(
                        order: order,
                        type: .heading,
                        text: collapseWhitespace(in: trimmed),
                        headingLevel: headingLevel,
                        listStyle: nil,
                        listDepth: nil,
                        listIndex: nil
                    )
                )
                order += 1
                continue
            }

            blocks.append(
                ReadableBlock(
                    order: order,
                    type: .paragraph,
                    text: collapseWhitespace(in: trimmed),
                    headingLevel: nil,
                    listStyle: nil,
                    listDepth: nil,
                    listIndex: nil
                )
            )
            order += 1
        }

        return blocks
    }

    private func paragraphRanges(in attributedString: NSAttributedString) -> [NSRange] {
        let fullString = attributedString.string as NSString
        var ranges: [NSRange] = []
        fullString.enumerateSubstrings(in: NSRange(location: 0, length: fullString.length), options: .byParagraphs) { _, range, _, _ in
            ranges.append(range)
        }
        return ranges
    }

    private func estimateBodyFontSize(for attributedString: NSAttributedString, ranges: [NSRange]) -> CGFloat {
        var sizes: [CGFloat] = []
        for range in ranges {
            let stats = fontStats(in: range, attributedString: attributedString)
            if stats.maxSize > 0 {
                sizes.append(stats.maxSize)
            }
        }
        guard !sizes.isEmpty else {
            return 12
        }
        let sorted = sizes.sorted()
        return sorted[sorted.count / 2]
    }

    private func fontStats(in range: NSRange, attributedString: NSAttributedString) -> (maxSize: CGFloat, isBold: Bool) {
        var maxSize: CGFloat = 0
        var isBold = false

        attributedString.enumerateAttribute(.font, in: range, options: []) { value, _, _ in
            guard let font = value as? NSFont else { return }
            maxSize = max(maxSize, font.pointSize)
            if font.fontDescriptor.symbolicTraits.contains(.bold) {
                isBold = true
            }
        }

        return (maxSize == 0 ? 12 : maxSize, isBold)
    }

    private func headingLevel(for text: String, fontSize: CGFloat, bodyFontSize: CGFloat, isBold: Bool) -> Int? {
        let ratio = fontSize / max(bodyFontSize, 1)
        if ratio >= 1.8 {
            return 1
        }
        if ratio >= 1.5 {
            return 2
        }
        if ratio >= 1.3 {
            return 3
        }
        if isBold, looksLikeHeading(text) {
            return 4
        }
        return nil
    }

    private func looksLikeHeading(_ line: String) -> Bool {
        guard line.count <= 80 else { return false }
        guard !line.hasSuffix(".") else { return false }

        let words = line.split(whereSeparator: \.isWhitespace)
        guard (1...10).contains(words.count) else { return false }

        let letters = line.filter(\.isLetter)
        guard letters.count >= 3 else { return false }

        let uppercaseLetters = letters.filter(\.isUppercase).count
        if uppercaseLetters == letters.count {
            return true
        }

        let titleCaseWordCount = words.filter { word in
            guard let firstCharacter = word.first else { return false }
            return firstCharacter.isUppercase
        }.count

        return titleCaseWordCount >= max(1, words.count - 1)
    }

    private func listMatch(for text: String, paragraphStyle: NSParagraphStyle?) -> (text: String, depth: Int, style: ReadableListStyle, index: Int?)? {
        if let paragraphStyle, !paragraphStyle.textLists.isEmpty {
            let depth = max(0, paragraphStyle.textLists.count - 1)
            let markerFormat = paragraphStyle.textLists.last?.markerFormat.rawValue.lowercased() ?? ""
            let isOrdered = markerFormat.contains("decimal") || markerFormat.contains("upper") || markerFormat.contains("lower")
            let style: ReadableListStyle = isOrdered ? .ordered : .unordered
            return (stripListPrefix(from: text), depth, style, nil)
        }

        let range = NSRange(location: 0, length: text.utf16.count)
        guard let match = listItemRegex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 2,
              let markerRange = Range(match.range(at: 1), in: text),
              let textRange = Range(match.range(at: 2), in: text) else {
            return nil
        }

        let marker = String(text[markerRange])
        let itemText = collapseWhitespace(in: String(text[textRange]))
        let numericMarker = marker.trimmingCharacters(in: CharacterSet(charactersIn: ".)"))
        let index = Int(numericMarker)
        let isOrdered = index != nil || marker.range(of: "[A-Za-z]", options: .regularExpression) != nil
        let style: ReadableListStyle = isOrdered ? .ordered : .unordered

        return (itemText, 0, style, index)
    }

    private func stripListPrefix(from text: String) -> String {
        let range = NSRange(location: 0, length: text.utf16.count)
        guard let match = listItemRegex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 2,
              let itemRange = Range(match.range(at: 2), in: text) else {
            return collapseWhitespace(in: text)
        }

        return collapseWhitespace(in: String(text[itemRange]))
    }

    private func parseMarkdownHeading(in line: String) -> (level: Int, text: String)? {
        let range = NSRange(location: 0, length: line.utf16.count)
        guard let match = markdownHeadingRegex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges > 2,
              let levelRange = Range(match.range(at: 1), in: line),
              let textRange = Range(match.range(at: 2), in: line) else {
            return nil
        }

        let level = line[levelRange].count
        let text = collapseWhitespace(in: String(line[textRange]))
        return (max(1, min(6, level)), text)
    }

    private func collapseWhitespace(in text: String) -> String {
        return text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
