import Foundation
import PDFKit

nonisolated final class PDFTextParser {
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

            // Recurrence alone cannot prove a line is cosmetic. Preserve every
            // extracted line until provenance-aware layout evidence can do so.
            return mergeWrappedBlocks(blocks)
        }
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

}
