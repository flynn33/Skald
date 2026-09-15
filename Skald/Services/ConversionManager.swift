import Foundation

nonisolated final class ConversionManager: @unchecked Sendable {
    private let fileManager: FileManager
    private let converters: [DocumentConverter]
    private let outputFilePlanner: OutputFilePlanning
    private let outputWriter: OutputWriting

    // Dependency injection for testing/debugging.
    // Order matters: dispatch is first-match-by-extension, so structured
    // converters precede the broad text catch-all (SourceTextConverter), which
    // must stay last so it never shadows json/csv/md and friends.
    init(
        fileManager: FileManager = .default,
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
        ],
        outputFilePlanner: OutputFilePlanning? = nil,
        outputWriter: OutputWriting? = nil
    ) {
        self.fileManager = fileManager
        self.converters = converters
        self.outputFilePlanner = outputFilePlanner ?? OutputFilePlanner(fileManager: fileManager)
        self.outputWriter = outputWriter ?? OutputWriter(planner: self.outputFilePlanner)
    }

    func convertFiles(in sourceURL: URL, to targetURL: URL, format: OutputFormat, delimitedOptions: DelimitedOptions = DelimitedOptions()) throws -> ConversionReport {
        let startedAt = Date()

        // Conversion runs off the main queue, so explicitly hold security-scoped
        // access to the user-selected source and target folders for the whole
        // batch. Child URLs enumerated below inherit the folder scope.
        let sourceScoped = sourceURL.startAccessingSecurityScopedResource()
        let targetScoped = targetURL.startAccessingSecurityScopedResource()
        defer {
            if sourceScoped { sourceURL.stopAccessingSecurityScopedResource() }
            if targetScoped { targetURL.stopAccessingSecurityScopedResource() }
        }

        let files = try fileManager.contentsOfDirectory(
            at: sourceURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
        let sortedFiles = files.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }

        var entries: [ConversionEntry] = []
        var convertedCount = 0
        var emptyCount = 0
        var skippedCount = 0
        var failedCount = 0
        var reservedOutputPaths = Set<String>()

        for fileURL in sortedFiles {
            let source = SourceFileDescriptor(url: fileURL)

            if let isDirectory = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
               isDirectory == true {
                entries.append(
                    ConversionEntry(
                        fileName: source.reportBaseName,
                        fileExtension: source.fileExtension,
                        status: .skipped,
                        message: "Directory.",
                        outputURL: nil
                    )
                )
                skippedCount += 1
                continue
            }

            let converter = converters.first { $0.supportedExtensions.contains(source.fileExtension) }

            if source.isHidden, converter == nil {
                entries.append(
                    ConversionEntry(
                        fileName: source.reportBaseName,
                        fileExtension: source.fileExtension,
                        status: .skipped,
                        message: "Hidden file.",
                        outputURL: nil
                    )
                )
                skippedCount += 1
                continue
            }

            guard let converter else {
                let detail = source.fileExtension.isEmpty ? "no file extension" : ".\(source.fileExtension)"
                entries.append(
                    ConversionEntry(
                        fileName: source.reportBaseName,
                        fileExtension: source.fileExtension,
                        status: .skipped,
                        message: "Unsupported file type (\(detail)).",
                        outputURL: nil
                    )
                )
                skippedCount += 1
                continue
            }

            do {
                let output: String
                let appliedSettings: AppliedDelimitedSettings?
                let isEmpty: Bool
                if let delimited = converter as? DelimitedTextConverter {
                    let result = try delimited.convert(at: fileURL, to: format, options: delimitedOptions)
                    output = result.output
                    appliedSettings = result.appliedSettings
                    isEmpty = result.isEmpty
                } else {
                    output = try converter.convert(at: fileURL, to: format)
                    appliedSettings = nil
                    isEmpty = false
                }
                let outputExtension = format == .markdown ? "md" : "json"
                let outputPlan = try outputWriter.publish(
                    Data(output.utf8),
                    for: fileURL,
                    in: targetURL,
                    outputExtension: outputExtension,
                    reservedOutputPaths: reservedOutputPaths
                )
                let outputPath = normalizedPath(for: outputPlan.url)
                reservedOutputPaths.insert(outputPath)

                var notes: [String] = []
                if outputPlan.wasRenamed { notes.append("Saved as \(outputPlan.url.lastPathComponent) to avoid overwriting another file.") }
                if let appliedSettings {
                    notes.append("Import: \(appliedSettings.encoding), delimiter \(appliedSettings.delimiter.debugDescription), header \(appliedSettings.headerMode).")
                    if !appliedSettings.diagnostics.isEmpty { notes.append("Warnings: \(appliedSettings.diagnostics.joined(separator: ", ")).") }
                }
                let message = notes.isEmpty ? nil : notes.joined(separator: " ")
                entries.append(
                    ConversionEntry(
                        fileName: source.reportBaseName,
                        fileExtension: source.fileExtension,
                        status: isEmpty ? .empty : .converted,
                        message: message,
                        outputURL: outputPlan.url
                    )
                )
                if isEmpty { emptyCount += 1 } else { convertedCount += 1 }
            } catch {
                entries.append(
                    ConversionEntry(
                        fileName: source.reportBaseName,
                        fileExtension: source.fileExtension,
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
            emptyCount: emptyCount,
            skippedCount: skippedCount,
            failedCount: failedCount
        )
    }

    private func normalizedPath(for url: URL) -> String {
        url.standardizedFileURL.path.lowercased()
    }
}
