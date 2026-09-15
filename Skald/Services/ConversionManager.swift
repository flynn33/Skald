import Foundation

// Dependencies are immutable after initialization. The only mutable run state
// is protected by runLock; conversions never overlap on one manager instance.
nonisolated final class ConversionManager: @unchecked Sendable {
    private let fileManager: FileManager
    private let converters: [DocumentConverter]
    private let outputFilePlanner: OutputFilePlanning
    private let outputWriter: OutputWriting
    private let worklistBuilder = SourceWorklistBuilder()
    private let runLock = NSLock()
    private var runActive = false

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
        try convertSelections([sourceURL], to: targetURL, format: format, delimitedOptions: delimitedOptions)
    }

    func convertSelections(_ selections: [URL], to targetURL: URL, format: OutputFormat, delimitedOptions: DelimitedOptions = DelimitedOptions(), intakeOptions: IntakeOptions = IntakeOptions(), progress: ((Int, Int) -> Void)? = nil, isCancelled: (() -> Bool)? = nil) throws -> ConversionReport {
        runLock.lock()
        guard !runActive else {
            runLock.unlock()
            throw IntakeError.alreadyRunning
        }
        runActive = true
        runLock.unlock()
        defer {
            runLock.lock()
            runActive = false
            runLock.unlock()
        }
        let startedAt = Date()

        // Conversion runs off the main queue, so explicitly hold security-scoped
        // access to the user-selected source and target folders for the whole
        // batch. Child URLs enumerated below inherit the folder scope.
        let sourceScopes = selections.map { $0.startAccessingSecurityScopedResource() }
        let targetScoped = targetURL.startAccessingSecurityScopedResource()
        defer {
            for (url, started) in zip(selections, sourceScopes) where started { url.stopAccessingSecurityScopedResource() }
            if targetScoped { targetURL.stopAccessingSecurityScopedResource() }
        }

        // Freeze source identities before the first publication; generated
        // outputs cannot enter this run even when source and target are equal.
        let worklist = try worklistBuilder.snapshot(selections: selections, target: targetURL, options: intakeOptions)

        var entries: [ConversionEntry] = []
        var convertedCount = 0
        var partialCount = 0
        var emptyCount = 0
        var skippedCount = 0
        var failedCount = 0
        var wasCancelled = false
        var reservedOutputPaths = Set<String>()

        for (position, item) in worklist.items.enumerated() {
            if Task.isCancelled || isCancelled?() == true { wasCancelled = true; break }
            progress?(position, worklist.items.count)
            let fileURL = item.url
            let source = SourceFileDescriptor(url: fileURL)

            if !item.isConvertible {
                let denied = item.message?.hasPrefix("Cannot") == true
                entries.append(
                    ConversionEntry(
                        fileName: source.reportBaseName,
                        fileExtension: source.fileExtension,
                        status: denied ? .failed : .skipped,
                        message: item.message,
                        outputURL: nil
                    )
                )
                if denied { failedCount += 1 } else { skippedCount += 1 }
                continue
            }

            var converter = converters.first { $0.supportedExtensions.contains(source.fileExtension) }
            do {
                let result = try ContentProbe().inspect(fileURL, fileExtension: source.fileExtension, knownExtension: converter != nil)
                switch result {
                case .compatible: break
                case .strictText:
                    converter = converters.first { $0 is TextConverter } ?? TextConverter()
                case .binary:
                    entries.append(ConversionEntry(fileName: source.reportBaseName, fileExtension: source.fileExtension, status: .skipped, message: "Unknown binary input.", outputURL: nil))
                    skippedCount += 1
                    continue
                case .extensionConflict(let signature):
                    entries.append(ConversionEntry(fileName: source.reportBaseName, fileExtension: source.fileExtension, status: .failed, message: "extensionContentMismatch: .\(source.fileExtension) conflicts with \(signature) content.", outputURL: nil))
                    failedCount += 1
                    continue
                }
            } catch {
                entries.append(ConversionEntry(fileName: source.reportBaseName, fileExtension: source.fileExtension, status: .failed, message: "Cannot probe input: \(error.localizedDescription)", outputURL: nil))
                failedCount += 1
                continue
            }

            guard let converter else {
                let detail = source.fileExtension.isEmpty ? "no file extension" : ".\(source.fileExtension)"
                entries.append(
                    ConversionEntry(
                        fileName: source.reportBaseName,
                        fileExtension: source.fileExtension,
                        status: .skipped,
                        message: "Unsupported file type (\(detail)); content was not confirmed text.",
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
                let isPartial: Bool
                let extractorWarnings: [String]
                if let delimited = converter as? DelimitedTextConverter {
                    let result = try delimited.convert(at: fileURL, to: format, options: delimitedOptions)
                    output = result.output
                    appliedSettings = result.appliedSettings
                    isEmpty = result.isEmpty
                    isPartial = false
                    extractorWarnings = []
                } else {
                    let result = try converter.convertDetailed(at: fileURL, to: format)
                    output = result.output
                    appliedSettings = nil
                    isEmpty = result.quality == .empty
                    isPartial = result.quality == .partial
                    extractorWarnings = result.warnings
                }
                if Task.isCancelled || isCancelled?() == true { wasCancelled = true; break }
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
                if !extractorWarnings.isEmpty { notes.append("Extraction warnings: \(extractorWarnings.joined(separator: ", ")).") }
                let message = notes.isEmpty ? nil : notes.joined(separator: " ")
                entries.append(
                    ConversionEntry(
                        fileName: source.reportBaseName,
                        fileExtension: source.fileExtension,
                        status: isPartial ? .partial : (isEmpty ? .empty : .converted),
                        message: message,
                        outputURL: outputPlan.url
                    )
                )
                if isPartial { partialCount += 1 } else if isEmpty { emptyCount += 1 } else { convertedCount += 1 }
            } catch OutputPublicationError.cancelled {
                wasCancelled = true
                break
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
        progress?(entries.count, worklist.items.count)

        return ConversionReport(
            startedAt: startedAt,
            finishedAt: Date(),
            entries: entries,
            plannedCount: worklist.items.count,
            convertedCount: convertedCount,
            partialCount: partialCount,
            emptyCount: emptyCount,
            skippedCount: skippedCount,
            failedCount: failedCount,
            wasCancelled: wasCancelled
        )
    }

    private func normalizedPath(for url: URL) -> String {
        url.standardizedFileURL.path.lowercased()
    }
}
