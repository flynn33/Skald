import Foundation

nonisolated final class ConversionManager: @unchecked Sendable {
    private let fileManager: FileManager
    private let converters: [DocumentConverter]

    // Dependency injection for testing/debugging
    // Order matters: dispatch is first-match-by-extension, so structured
    // converters precede the broad text catch-all (SourceTextConverter), which
    // must stay last so it never shadows json/csv/md and friends.
    init(fileManager: FileManager = .default,
         converters: [DocumentConverter] = [
            PDFConverter(),
            AttributedDocumentConverter(),
            DelimitedTextConverter(),
            JSONConverter(),
            XMLConverter(),
            PropertyListConverter(),
            IniConverter(),
            ImageOCRConverter(),
            TextConverter(),
            SourceTextConverter()
         ]) {
        self.fileManager = fileManager
        self.converters = converters
    }

    func convertFiles(in sourceURL: URL, to targetURL: URL, format: OutputFormat) throws -> ConversionReport {
        let startedAt = Date()

        // Conversion runs off the main queue, so explicitly hold security-scoped
        // access to the user-selected source and target folders for the whole
        // batch. Without this, out-of-process readers like PDFKit can fail to
        // open files that in-process readers (FileManager/NSAttributedString)
        // would still read. Child URLs enumerated below inherit the folder scope.
        let sourceScoped = sourceURL.startAccessingSecurityScopedResource()
        let targetScoped = targetURL.startAccessingSecurityScopedResource()
        defer {
            if sourceScoped { sourceURL.stopAccessingSecurityScopedResource() }
            if targetScoped { targetURL.stopAccessingSecurityScopedResource() }
        }

        let files = try fileManager.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: [.isDirectoryKey])
        let sortedFiles = files.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

        var entries: [ConversionEntry] = []
        var convertedCount = 0
        var skippedCount = 0
        var failedCount = 0

        for fileURL in sortedFiles {
            let fileName = fileURL.deletingPathExtension().lastPathComponent
            let fileExtension = fileURL.pathExtension.lowercased()

            if fileName.hasPrefix(".") {
                entries.append(
                    ConversionEntry(
                        fileName: fileName,
                        fileExtension: fileExtension,
                        status: .skipped,
                        message: "Hidden file.",
                        outputURL: nil
                    )
                )
                skippedCount += 1
                continue
            }

            if let isDirectory = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDirectory == true {
                entries.append(
                    ConversionEntry(
                        fileName: fileName,
                        fileExtension: fileExtension,
                        status: .skipped,
                        message: "Directory.",
                        outputURL: nil
                    )
                )
                skippedCount += 1
                continue
            }

            guard let converter = converters.first(where: { $0.supportedExtensions.contains(fileExtension) }) else {
                let detail = fileExtension.isEmpty ? "no file extension" : ".\(fileExtension)"
                entries.append(
                    ConversionEntry(
                        fileName: fileName,
                        fileExtension: fileExtension,
                        status: .skipped,
                        message: "Unsupported file type (\(detail)).",
                        outputURL: nil
                    )
                )
                skippedCount += 1
                continue
            }

            do {
                let output = try converter.convert(at: fileURL, to: format)

                let outputExt = format == .markdown ? "md" : "json"
                let outputURL = targetURL
                    .appendingPathComponent(fileName)
                    .appendingPathExtension(outputExt)

                try output.write(to: outputURL, atomically: true, encoding: .utf8)

                entries.append(
                    ConversionEntry(
                        fileName: fileName,
                        fileExtension: fileExtension,
                        status: .converted,
                        message: nil,
                        outputURL: outputURL
                    )
                )
                convertedCount += 1
            } catch {
                entries.append(
                    ConversionEntry(
                        fileName: fileName,
                        fileExtension: fileExtension,
                        status: .failed,
                        message: error.localizedDescription,
                        outputURL: nil
                    )
                )
                failedCount += 1
            }
        }

        return ConversionReport(
            startedAt: startedAt,
            finishedAt: Date(),
            entries: entries,
            convertedCount: convertedCount,
            skippedCount: skippedCount,
            failedCount: failedCount
        )
    }
}
