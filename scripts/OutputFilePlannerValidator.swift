import Foundation

private enum ValidationFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

@main
struct OutputFilePlannerValidatorTool {
    static func main() {
        do {
            try runValidation()
            print("Output file planner validated successfully.")
        } catch {
            print("Output file planner validation failed: \(error)")
            exit(1)
        }
    }

    private static func runValidation() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("SkaldOutputPlanner-\(UUID().uuidString)", isDirectory: true)
        let sourceDirectoryURL = rootURL.appendingPathComponent("source", isDirectory: true)
        let targetDirectoryURL = rootURL.appendingPathComponent("target", isDirectory: true)

        try fileManager.createDirectory(at: sourceDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: targetDirectoryURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        let planner = OutputFilePlanner(fileManager: fileManager)
        let sourcePDFURL = sourceDirectoryURL.appendingPathComponent("report.pdf")
        try Data().write(to: sourcePDFURL)

        let preferred = planner.planOutput(
            for: sourcePDFURL,
            in: targetDirectoryURL,
            outputExtension: "md",
            reservedOutputPaths: []
        )
        try require(preferred.url.lastPathComponent == "report.md", "Expected the preferred report.md output name.")
        try require(!preferred.wasRenamed, "Preferred output should not be marked as renamed.")

        try Data().write(to: preferred.url)
        let existingCollision = planner.planOutput(
            for: sourcePDFURL,
            in: targetDirectoryURL,
            outputExtension: "md",
            reservedOutputPaths: []
        )
        try require(existingCollision.url.lastPathComponent == "report-pdf.md", "Existing output must not be overwritten.")
        try require(existingCollision.wasRenamed, "Collision output should be marked as renamed.")

        let sourceMarkdownURL = targetDirectoryURL.appendingPathComponent("notes.md")
        try Data("original".utf8).write(to: sourceMarkdownURL)
        let sourceCollision = planner.planOutput(
            for: sourceMarkdownURL,
            in: targetDirectoryURL,
            outputExtension: "md",
            reservedOutputPaths: []
        )
        try require(sourceCollision.url.lastPathComponent == "notes-md.md", "Source files must never be selected as output destinations.")

        let duplicateSourceURL = sourceDirectoryURL.appendingPathComponent("data.csv")
        try Data().write(to: duplicateSourceURL)
        let reservedPath = targetDirectoryURL.appendingPathComponent("data.md").standardizedFileURL.path.lowercased()
        let reservedCollision = planner.planOutput(
            for: duplicateSourceURL,
            in: targetDirectoryURL,
            outputExtension: "md",
            reservedOutputPaths: [reservedPath]
        )
        try require(reservedCollision.url.lastPathComponent == "data-csv.md", "Reserved batch outputs must receive unique names.")

        let environmentURL = sourceDirectoryURL.appendingPathComponent(".env")
        let environmentDescriptor = SourceFileDescriptor(url: environmentURL)
        try require(environmentDescriptor.baseName == "env", "Extension-only dotfiles need a visible output base name.")
        try require(environmentDescriptor.fileExtension == "env", "Extension-only dotfiles need a resolvable converter extension.")
        try require(environmentDescriptor.reportBaseName.isEmpty, "Extension-only dotfiles must render with their original leading dot in reports.")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw ValidationFailure.failed(message)
        }
    }
}
