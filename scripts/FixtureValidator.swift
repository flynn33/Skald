import Foundation

private struct FixtureCase {
    let inputURL: URL
    let expectedMarkdownURL: URL
    let expectedJSONURL: URL
}

private struct FixtureFailure {
    let fileName: String
    let format: String
    let message: String
}

private final class FixtureValidator {
    private let rootURL: URL
    private let fixturesURL: URL
    private let inputURL: URL
    private let expectedMarkdownURL: URL
    private let expectedJSONURL: URL
    private let converters: [DocumentConverter]

    init(rootURL: URL) {
        self.rootURL = rootURL
        self.fixturesURL = rootURL.appendingPathComponent("Fixtures")
        self.inputURL = fixturesURL.appendingPathComponent("input")
        self.expectedMarkdownURL = fixturesURL.appendingPathComponent("expected/markdown")
        self.expectedJSONURL = fixturesURL.appendingPathComponent("expected/json")
        self.converters = [
            DelimitedTextConverter(),
            JSONConverter(),
            XMLConverter(),
            PropertyListConverter(),
            IniConverter(),
            TextConverter(),
            SourceTextConverter()
        ]
    }

    func run() -> Int {
        do {
            let fixtures = try loadFixtures()
            if fixtures.isEmpty {
                print("No fixtures found in \(inputURL.path)")
                return 1
            }

            let outputURL = try prepareOutputDirectory()
            var failures: [FixtureFailure] = []

            for fixture in fixtures {
                let fileName = fixture.inputURL.lastPathComponent
                guard let converter = converters.first(where: { $0.supportedExtensions.contains(fixture.inputURL.pathExtension.lowercased()) }) else {
                    failures.append(FixtureFailure(fileName: fileName, format: "all", message: "No converter registered for extension."))
                    continue
                }

                do {
                    let markdownOutput = try converter.convert(at: fixture.inputURL, to: .markdown)
                    let markdownPath = outputURL.appendingPathComponent(fixture.expectedMarkdownURL.lastPathComponent)
                    try markdownOutput.write(to: markdownPath, atomically: true, encoding: .utf8)
                    if !compareMarkdown(markdownOutput, expectedURL: fixture.expectedMarkdownURL) {
                        failures.append(FixtureFailure(fileName: fileName, format: "markdown", message: "Output did not match expected markdown."))
                    }

                    let jsonOutput = try converter.convert(at: fixture.inputURL, to: .json)
                    let jsonPath = outputURL.appendingPathComponent(fixture.expectedJSONURL.lastPathComponent)
                    try jsonOutput.write(to: jsonPath, atomically: true, encoding: .utf8)
                    if !compareJSON(jsonOutput, expectedURL: fixture.expectedJSONURL) {
                        failures.append(FixtureFailure(fileName: fileName, format: "json", message: "Output did not match expected JSON (after normalization)."))
                    }
                } catch {
                    failures.append(FixtureFailure(fileName: fileName, format: "all", message: error.localizedDescription))
                }
            }

            if failures.isEmpty {
                print("Fixtures validated successfully (\(fixtures.count) files).")
                print("Generated outputs in: \(outputURL.path)")
                return 0
            }

            print("Fixtures validation failed:")
            for failure in failures {
                print("- \(failure.fileName) [\(failure.format)]: \(failure.message)")
            }
            print("Generated outputs in: \(outputURL.path)")
            return 2
        } catch {
            print("Validation failed: \(error.localizedDescription)")
            return 3
        }
    }

    private func loadFixtures() throws -> [FixtureCase] {
        let files = try FileManager.default.contentsOfDirectory(at: inputURL, includingPropertiesForKeys: nil)
        let sortedFiles = files.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

        return sortedFiles.compactMap { fileURL in
            let baseName = fileURL.deletingPathExtension().lastPathComponent
            guard !baseName.isEmpty else { return nil }
            let expectedMarkdown = expectedMarkdownURL.appendingPathComponent(baseName).appendingPathExtension("md")
            let expectedJSON = expectedJSONURL.appendingPathComponent(baseName).appendingPathExtension("json")
            return FixtureCase(inputURL: fileURL, expectedMarkdownURL: expectedMarkdown, expectedJSONURL: expectedJSON)
        }
    }

    private func prepareOutputDirectory() throws -> URL {
        let outputURL = fixturesURL.appendingPathComponent("output")
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        return outputURL
    }

    private func compareMarkdown(_ output: String, expectedURL: URL) -> Bool {
        guard let expected = try? String(contentsOf: expectedURL, encoding: .utf8) else {
            return false
        }
        return normalizeNewlines(output) == normalizeNewlines(expected)
    }

    private func compareJSON(_ output: String, expectedURL: URL) -> Bool {
        guard let expected = try? String(contentsOf: expectedURL, encoding: .utf8) else {
            return false
        }

        guard let normalizedOutput = normalizeJSON(output),
              let normalizedExpected = normalizeJSON(expected) else {
            return false
        }

        return normalizedOutput == normalizedExpected
    }

    private func normalizeJSON(_ jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return nil
        }

        let scrubbed = scrubConvertedAt(in: jsonObject)
        guard JSONSerialization.isValidJSONObject(scrubbed),
              let normalizedData = try? JSONSerialization.data(withJSONObject: scrubbed, options: [.sortedKeys]) else {
            return nil
        }

        return String(data: normalizedData, encoding: .utf8)
    }

    private func scrubConvertedAt(in value: Any) -> Any {
        if var dict = value as? [String: Any] {
            for (key, nestedValue) in dict {
                if key == "convertedAt" {
                    dict[key] = "REDACTED"
                } else {
                    dict[key] = scrubConvertedAt(in: nestedValue)
                }
            }
            return dict
        }

        if let array = value as? [Any] {
            return array.map { scrubConvertedAt(in: $0) }
        }

        return value
    }

    private func normalizeNewlines(_ text: String) -> String {
        return text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}

@main
struct FixtureValidatorTool {
    static func main() {
        let arguments = CommandLine.arguments
        let rootPath: String
        if arguments.count > 1 {
            rootPath = arguments[1]
        } else {
            rootPath = FileManager.default.currentDirectoryPath
        }

        let rootURL = URL(fileURLWithPath: rootPath)
        let validator = FixtureValidator(rootURL: rootURL)
        let exitCode = validator.run()
        exit(Int32(exitCode))
    }
}
