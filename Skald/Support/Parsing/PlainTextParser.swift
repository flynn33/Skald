import Foundation

nonisolated final class PlainTextParser {
    private struct ListMatch {
        let indent: Int
        let style: ReadableListStyle
        let index: Int?
        let text: String
    }

    private struct DraftListItem {
        let indent: Int
        let depth: Int
        let style: ReadableListStyle
        let index: Int?
        var lines: [String]
    }

    private let markdownHeadingRegex = try! NSRegularExpression(pattern: "^(#{1,6})\\s+(.+)$")
    private let listItemRegex = try! NSRegularExpression(pattern: "^(\\s*)([-*]|\\d+[.)]|[A-Za-z][.)])\\s+(.+)$")

    func parse(_ text: String) -> [ReadableBlock] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2022}", with: "- ")

        let lines = normalized.components(separatedBy: .newlines)
        var blocks: [ReadableBlock] = []
        var order = 1
        var paragraphBuffer: [String] = []
        var pendingListItem: DraftListItem?

        func appendBlock(
            type: ReadableBlockType,
            text: String,
            headingLevel: Int? = nil,
            listStyle: ReadableListStyle? = nil,
            listDepth: Int? = nil,
            listIndex: Int? = nil
        ) {
            blocks.append(
                ReadableBlock(
                    order: order,
                    type: type,
                    text: text,
                    headingLevel: headingLevel,
                    listStyle: listStyle,
                    listDepth: listDepth,
                    listIndex: listIndex
                )
            )
            order += 1
        }

        func flushParagraphBuffer() {
            guard !paragraphBuffer.isEmpty else { return }
            let merged = mergeParagraphLines(paragraphBuffer)
            if !merged.isEmpty {
                appendBlock(type: .paragraph, text: merged)
            }
            paragraphBuffer.removeAll(keepingCapacity: true)
        }

        func flushListItem() {
            guard let pending = pendingListItem else { return }
            let merged = mergeParagraphLines(pending.lines)
            if !merged.isEmpty {
                appendBlock(
                    type: .listItem,
                    text: merged,
                    listStyle: pending.style,
                    listDepth: pending.depth,
                    listIndex: pending.index
                )
            }
            pendingListItem = nil
        }

        var index = 0
        while index < lines.count {
            let rawLine = lines[index]
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let nextTrimmed = (index + 1 < lines.count)
                ? lines[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
                : ""

            if trimmed.isEmpty {
                flushParagraphBuffer()
                flushListItem()
                index += 1
                continue
            }

            if let markdownHeading = parseMarkdownHeading(in: trimmed) {
                flushParagraphBuffer()
                flushListItem()
                appendBlock(type: .heading, text: markdownHeading.text, headingLevel: markdownHeading.level)
                index += 1
                continue
            }

            if let underlineHeading = parseUnderlineHeading(current: trimmed, next: nextTrimmed) {
                flushParagraphBuffer()
                flushListItem()
                appendBlock(type: .heading, text: underlineHeading.text, headingLevel: underlineHeading.level)
                index += 2
                continue
            }

            if let listMatch = parseListItem(in: rawLine) {
                flushParagraphBuffer()
                flushListItem()
                pendingListItem = DraftListItem(
                    indent: listMatch.indent,
                    depth: max(0, listMatch.indent / 2),
                    style: listMatch.style,
                    index: listMatch.index,
                    lines: [listMatch.text]
                )
                index += 1
                continue
            }

            if let pending = pendingListItem,
               isContinuationLine(rawLine, baseIndent: pending.indent) {
                pendingListItem?.lines.append(trimmed)
                index += 1
                continue
            }

            if looksLikeHeading(trimmed, nextLineIsBreak: nextTrimmed.isEmpty) {
                flushParagraphBuffer()
                flushListItem()
                appendBlock(type: .heading, text: collapseWhitespace(in: trimmed), headingLevel: 1)
                index += 1
                continue
            }

            flushListItem()
            paragraphBuffer.append(trimmed)
            index += 1
        }

        flushParagraphBuffer()
        flushListItem()
        return blocks
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

    private func parseUnderlineHeading(current: String, next: String) -> (level: Int, text: String)? {
        guard !current.isEmpty else { return nil }
        let underline = next.trimmingCharacters(in: .whitespacesAndNewlines)
        guard underline.count >= 3 else { return nil }

        if underline.allSatisfy({ $0 == "=" }) {
            return (1, collapseWhitespace(in: current))
        }

        if underline.allSatisfy({ $0 == "-" }) {
            return (2, collapseWhitespace(in: current))
        }

        return nil
    }

    private func parseListItem(in line: String) -> ListMatch? {
        let range = NSRange(location: 0, length: line.utf16.count)
        guard let match = listItemRegex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges > 3,
              let indentRange = Range(match.range(at: 1), in: line),
              let markerRange = Range(match.range(at: 2), in: line),
              let textRange = Range(match.range(at: 3), in: line) else {
            return nil
        }

        let indentString = String(line[indentRange])
        let marker = String(line[markerRange])
        let text = collapseWhitespace(in: String(line[textRange]))
        let indent = indentationWidth(indentString)

        let numericMarker = marker.trimmingCharacters(in: CharacterSet(charactersIn: ".)"))
        let index = Int(numericMarker)
        let isOrdered = index != nil || marker.range(of: "[A-Za-z]", options: .regularExpression) != nil
        let style: ReadableListStyle = isOrdered ? .ordered : .unordered

        return ListMatch(indent: indent, style: style, index: index, text: text)
    }

    private func isContinuationLine(_ line: String, baseIndent: Int) -> Bool {
        let indent = indentationWidth(prefixWhitespace(in: line))
        return indent > baseIndent
    }

    private func prefixWhitespace(in line: String) -> String {
        var whitespace = ""
        for char in line {
            if char == " " || char == "\t" {
                whitespace.append(char)
            } else {
                break
            }
        }
        return whitespace
    }

    private func indentationWidth(_ whitespace: String) -> Int {
        var width = 0
        for char in whitespace {
            if char == "\t" {
                width += 4
            } else {
                width += 1
            }
        }
        return width
    }

    private func looksLikeHeading(_ line: String, nextLineIsBreak: Bool) -> Bool {
        guard nextLineIsBreak else { return false }
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

    private func mergeParagraphLines(_ lines: [String]) -> String {
        var merged = ""

        for rawLine in lines {
            let line = collapseWhitespace(in: rawLine)
            guard !line.isEmpty else { continue }

            if merged.isEmpty {
                merged = line
                continue
            }

            if merged.hasSuffix("-"), let first = line.first, first.isLetter {
                merged.removeLast()
                merged += line
            } else {
                merged += " " + line
            }
        }

        return merged
    }

    private func collapseWhitespace(in text: String) -> String {
        return text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
