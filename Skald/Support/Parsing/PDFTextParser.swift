import Foundation
import PDFKit

nonisolated final class PDFTextParser {
    private enum LinePosition {
        case header
        case footer
    }

    private let attributedParser = AttributedTextParser()
    private let plainTextParser = PlainTextParser()

    func parsePages(from document: PDFDocument) -> [[ReadableBlock]] {
        let pageCount = document.pageCount
        var pageTexts: [String] = []
        var attributedPages: [NSAttributedString?] = []

        for index in 0..<pageCount {
            guard let page = document.page(at: index) else {
                pageTexts.append("")
                attributedPages.append(nil)
                continue
            }
            pageTexts.append(page.string ?? "")
            attributedPages.append(page.attributedString)
        }

        // A running header/footer is the first/last line that recurs across most
        // pages. Digit runs are folded so page-number footers ("Page 1", "Page 2")
        // are recognized as the same recurring line.
        let threshold = max(2, pageCount / 2)
        let commonHeader = commonRunningLine(in: pageTexts, position: .header, minOccurrences: threshold)
        let commonFooter = commonRunningLine(in: pageTexts, position: .footer, minOccurrences: threshold)

        return (0..<pageCount).map { index in
            // Prefer the attributed string: it carries font information the
            // attributed parser uses to detect headings and lists. Fall back to
            // plain text only when there is no usable attributed content (e.g.
            // image-only pages whose text came from elsewhere).
            let blocks: [ReadableBlock]
            if let attributed = attributedPages[index],
               !attributed.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks = attributedParser.parse(attributed)
            } else {
                blocks = plainTextParser.parse(pageTexts[index])
            }

            let withoutRunningLines = stripRunningLines(from: blocks, header: commonHeader, footer: commonFooter)
            return mergeWrappedBlocks(withoutRunningLines)
        }
    }

    // MARK: - Running header/footer detection

    private func commonRunningLine(in pageTexts: [String], position: LinePosition, minOccurrences: Int) -> String? {
        var counts: [String: Int] = [:]

        for text in pageTexts {
            let lines = nonEmptyLines(from: text)
            let candidate = position == .header ? lines.first : lines.last
            if let candidate {
                counts[normalizeForComparison(candidate), default: 0] += 1
            }
        }

        guard let best = counts.max(by: { $0.value < $1.value }), best.value >= minOccurrences else {
            return nil
        }

        // Returns the normalized (digit-folded) form; callers compare against it.
        return best.key.isEmpty ? nil : best.key
    }

    private func stripRunningLines(from blocks: [ReadableBlock], header: String?, footer: String?) -> [ReadableBlock] {
        var result = blocks

        // Never strip a heading block: a recurring heading (e.g. "Chapter 1",
        // "Chapter 2" on consecutive pages) is real content, whereas running
        // headers/footers are body-styled paragraphs.
        if let header, let first = result.first, first.type != .heading,
           normalizeForComparison(first.text) == header {
            result.removeFirst()
        }

        if let footer, let last = result.last, last.type != .heading,
           normalizeForComparison(last.text) == footer {
            result.removeLast()
        }

        return result
    }

    // MARK: - Wrapped-line reconstruction

    /// PDF text extraction breaks lines at visual wrap points rather than
    /// paragraph boundaries, so the per-line blocks produced upstream are merged
    /// back into paragraphs. Headings and list markers act as hard boundaries; a
    /// paragraph that follows another paragraph (or a list item) is joined unless
    /// the previous text clearly ended a sentence and the next clearly began one.
    private func mergeWrappedBlocks(_ blocks: [ReadableBlock]) -> [ReadableBlock] {
        var result: [ReadableBlock] = []

        for block in blocks {
            if block.type == .paragraph, let last = result.last {
                if last.type == .paragraph, continuesText(previous: last.text, next: block.text) {
                    result[result.count - 1] = replacingText(last, with: joinWrapped(last.text, block.text))
                    continue
                }

                if last.type == .listItem, !endsSentence(last.text) {
                    result[result.count - 1] = replacingText(last, with: joinWrapped(last.text, block.text))
                    continue
                }
            }

            result.append(block)
        }

        return result.enumerated().map { offset, block in
            replacingOrder(block, with: offset + 1)
        }
    }

    private func continuesText(previous: String, next: String) -> Bool {
        guard let nextFirst = next.trimmingCharacters(in: .whitespaces).first else { return false }
        let nextStartsNewSentence = nextFirst.isUppercase || nextFirst.isNumber
        return !(endsSentence(previous) && nextStartsNewSentence)
    }

    private func endsSentence(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespaces).last else { return false }
        return ".!?:;".contains(last)
    }

    private func joinWrapped(_ lhs: String, _ rhs: String) -> String {
        let right = rhs.trimmingCharacters(in: .whitespaces)
        // De-hyphenate words split across a line break ("multi-" + "page").
        if lhs.hasSuffix("-"), let first = right.first, first.isLetter {
            return String(lhs.dropLast()) + right
        }
        return lhs + " " + right
    }

    // MARK: - Block helpers (ReadableBlock is immutable)

    private func replacingText(_ block: ReadableBlock, with text: String) -> ReadableBlock {
        ReadableBlock(
            order: block.order,
            type: block.type,
            text: text,
            headingLevel: block.headingLevel,
            listStyle: block.listStyle,
            listDepth: block.listDepth,
            listIndex: block.listIndex
        )
    }

    private func replacingOrder(_ block: ReadableBlock, with order: Int) -> ReadableBlock {
        ReadableBlock(
            order: order,
            type: block.type,
            text: block.text,
            headingLevel: block.headingLevel,
            listStyle: block.listStyle,
            listDepth: block.listDepth,
            listIndex: block.listIndex
        )
    }

    // MARK: - Text utilities

    private func nonEmptyLines(from text: String) -> [String] {
        return text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Collapses whitespace and folds digit runs to a single "0" so that lines
    /// differing only by a page number compare as equal.
    private func normalizeForComparison(_ text: String) -> String {
        let collapsed = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        var output = ""
        var lastWasDigit = false
        for character in collapsed {
            if character.isNumber {
                if !lastWasDigit { output.append("0") }
                lastWasDigit = true
            } else {
                output.append(character)
                lastWasDigit = false
            }
        }
        return output.trimmingCharacters(in: .whitespaces)
    }
}
