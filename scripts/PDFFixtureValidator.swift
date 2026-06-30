import Foundation

// Validates (or regenerates) the committed digital-PDF fixture. Kept separate
// from FixtureValidator because it links PDFKit, which the dependency-light core
// validator deliberately avoids. PDF text extraction can vary across macOS
// versions, so this is a best-effort local check.
//
// Usage:
//   PDFFixtureValidator <repoRoot>            # check against expected
//   PDFFixtureValidator <repoRoot> --write    # regenerate expected outputs

private func scrubConvertedAt(in value: Any) -> Any {
    if var dict = value as? [String: Any] {
        for (key, nestedValue) in dict {
            dict[key] = key == "convertedAt" ? "REDACTED" : scrubConvertedAt(in: nestedValue)
        }
        return dict
    }
    if let array = value as? [Any] {
        return array.map { scrubConvertedAt(in: $0) }
    }
    return value
}

private func normalizeJSON(_ jsonString: String) -> String? {
    guard let data = jsonString.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
    let scrubbed = scrubConvertedAt(in: object)
    guard JSONSerialization.isValidJSONObject(scrubbed),
          let normalized = try? JSONSerialization.data(withJSONObject: scrubbed, options: [.sortedKeys]) else { return nil }
    return String(data: normalized, encoding: .utf8)
}

private func normalizeNewlines(_ text: String) -> String {
    text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
}

@main
struct PDFFixtureValidatorTool {
    static func main() {
        let arguments = CommandLine.arguments
        let root = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : ".")
        let write = arguments.contains("--write")

        let pdfURL = root.appendingPathComponent("Fixtures/pdf/sample-digital.pdf")
        let expectedDir = root.appendingPathComponent("Fixtures/pdf/expected")
        let expectedMarkdown = expectedDir.appendingPathComponent("sample-digital.md")
        let expectedJSON = expectedDir.appendingPathComponent("sample-digital.json")

        let converter = PDFConverter()
        do {
            let markdown = try converter.convert(at: pdfURL, to: .markdown)
            let json = try converter.convert(at: pdfURL, to: .json)

            if write {
                try FileManager.default.createDirectory(at: expectedDir, withIntermediateDirectories: true)
                try markdown.write(to: expectedMarkdown, atomically: true, encoding: .utf8)
                // Persist JSON with the timestamp scrubbed so the fixture stays stable.
                if let data = json.data(using: .utf8),
                   let object = try? JSONSerialization.jsonObject(with: data) {
                    let scrubbed = scrubConvertedAt(in: object)
                    let pretty = try JSONSerialization.data(withJSONObject: scrubbed, options: [.prettyPrinted, .sortedKeys])
                    try (String(data: pretty, encoding: .utf8)! + "\n").write(to: expectedJSON, atomically: true, encoding: .utf8)
                }
                print("Wrote expected PDF fixture outputs.")
                exit(0)
            }

            var failures: [String] = []
            if let expected = try? String(contentsOf: expectedMarkdown, encoding: .utf8) {
                if normalizeNewlines(markdown) != normalizeNewlines(expected) {
                    failures.append("markdown mismatch")
                }
            } else {
                failures.append("missing expected markdown")
            }

            if let expected = try? String(contentsOf: expectedJSON, encoding: .utf8) {
                if normalizeJSON(json) != normalizeJSON(expected) {
                    failures.append("json mismatch")
                }
            } else {
                failures.append("missing expected json")
            }

            if failures.isEmpty {
                print("PDF fixture validated successfully.")
                exit(0)
            }
            print("PDF fixture validation failed: \(failures.joined(separator: ", "))")
            exit(2)
        } catch {
            print("PDF fixture conversion error: \(error)")
            exit(3)
        }
    }
}
