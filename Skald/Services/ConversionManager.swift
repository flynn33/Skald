import Foundation
import OSLog

// Dependencies are immutable after initialization. The only mutable run state
// is protected by runLock; conversions never overlap on one manager instance.
nonisolated final class ConversionManager: @unchecked Sendable {
    private let fileManager: FileManager
    private let converters: [DocumentConverter]
    private let outputFilePlanner: OutputFilePlanning
    private let outputWriter: OutputWriting
    private let outputBundleWriter: OutputBundleWriting
    private let limits: ResourceLimits
    private let logger = Logger(subsystem: "com.daley.jim.Skald", category: "conversion")
    private let worklistBuilder = SourceWorklistBuilder()
    private let runLock = NSLock()
    private var runActive = false

    // Dependency injection for testing/debugging.
    // Order matters: dispatch is first-match-by-extension, so structured
    // converters precede the broad text catch-all (SourceTextConverter), which
    // must stay last so it never shadows json/csv/md and friends.
    init(
        fileManager: FileManager = .default,
        converters: [DocumentConverter]? = nil,
        limits: ResourceLimits = ResourceLimits(),
        outputFilePlanner: OutputFilePlanning? = nil,
        outputWriter: OutputWriting? = nil,
        outputBundleWriter: OutputBundleWriting? = nil
    ) {
        self.fileManager = fileManager
        self.limits = limits
        let defaultConverters: [DocumentConverter] = [
            PDFConverter(maximumInputBytes: limits.documentInputBytes),
            WorkbookConverter(limits: limits),
            AttributedDocumentConverter(maximumHTMLBytes: min(limits.textInputBytes, 8 * 1_024 * 1_024),
                                        maximumDocumentBytes: limits.documentInputBytes,
                                        maximumPackageEntries: limits.archiveEntries),
            DelimitedTextConverter(decoder: TextDecoder(maximumInputBytes: limits.delimitedInputBytes),
                                   parser: DelimitedTextParser(maximumRecords: limits.delimitedRecords,
                                   maximumColumns: limits.delimitedColumns, maximumCells: limits.delimitedCells,
                                   maximumFieldScalars: limits.delimitedFieldScalars)),
            JSONConverter(maximumInputBytes: limits.structuredInputBytes, maximumNodes: limits.valueNodes,
                          maximumDepth: limits.nestingDepth),
            XMLConverter(maximumInputBytes: limits.structuredInputBytes, maximumNodes: min(limits.valueNodes, 10_000),
                         maximumDepth: limits.nestingDepth),
            PropertyListConverter(maximumInputBytes: limits.structuredInputBytes, maximumNodes: limits.valueNodes,
                                  maximumDepth: limits.nestingDepth),
            IniConverter(maximumInputBytes: limits.textInputBytes, maximumRecords: limits.delimitedRecords,
                         maximumFieldScalars: limits.delimitedFieldScalars),
            ImageOCRConverter(maximumSourcePixels: limits.imageSourcePixels, maximumInputBytes: limits.imageInputBytes),
            TextConverter(maximumInputBytes: limits.textInputBytes),
            SourceTextConverter(maximumInputBytes: limits.textInputBytes)
        ]
        var configuredConverters = defaultConverters
        configuredConverters.insert(ZipCollectionConverter(memberConverters: defaultConverters,
            maximumInputBytes: limits.documentInputBytes, maximumEntries: limits.archiveEntries,
            maximumExpandedBytes: limits.archiveExpandedBytes, maximumMemberBytes: limits.documentInputBytes,
            maximumArchiveDepth: limits.archiveDepth), at: configuredConverters.count - 2)
        self.converters = converters ?? configuredConverters
        self.outputFilePlanner = outputFilePlanner ?? OutputFilePlanner(fileManager: fileManager)
        self.outputWriter = outputWriter ?? OutputWriter(planner: self.outputFilePlanner)
        self.outputBundleWriter = outputBundleWriter ?? OutputBundleWriter(fileManager: fileManager)
    }

    func convertFiles(in sourceURL: URL, to targetURL: URL, format: OutputFormat, delimitedOptions: DelimitedOptions = DelimitedOptions()) throws -> ConversionReport {
        try convertSelections([sourceURL], to: targetURL, mode: OutputMode(format), delimitedOptions: delimitedOptions)
    }

    func convertSelections(_ selections: [URL], to targetURL: URL, format: OutputFormat, delimitedOptions: DelimitedOptions = DelimitedOptions(), intakeOptions: IntakeOptions = IntakeOptions(), progress: ((Int, Int) -> Void)? = nil, isCancelled: (() -> Bool)? = nil) throws -> ConversionReport {
        try convertSelections(selections, to: targetURL, mode: OutputMode(format), bundleOriginal: false,
                              delimitedOptions: delimitedOptions, intakeOptions: intakeOptions,
                              progress: progress, isCancelled: isCancelled)
    }

    func convertFiles(in sourceURL: URL, to targetURL: URL, mode: OutputMode, bundleOriginal: Bool = false,
                      delimitedOptions: DelimitedOptions = DelimitedOptions()) throws -> ConversionReport {
        try convertSelections([sourceURL], to: targetURL, mode: mode, bundleOriginal: bundleOriginal,
                              delimitedOptions: delimitedOptions)
    }

    func convertSelections(_ selections: [URL], to targetURL: URL, mode: OutputMode, bundleOriginal: Bool = false,
                           delimitedOptions: DelimitedOptions = DelimitedOptions(),
                           intakeOptions: IntakeOptions = IntakeOptions(), progress: ((Int, Int) -> Void)? = nil,
                           isCancelled: (() -> Bool)? = nil) throws -> ConversionReport {
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
        try limits.validate()

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
        let boundedIntake = IntakeOptions(recursive: intakeOptions.recursive, includeHidden: intakeOptions.includeHidden,
                                          maximumItems: min(intakeOptions.maximumItems, limits.workItems),
                                          maximumDepth: min(intakeOptions.maximumDepth, limits.nestingDepth))
        let worklist = try worklistBuilder.snapshot(selections: selections, target: targetURL, options: boundedIntake)

        var entries: [ConversionEntry] = []
        var convertedCount = 0
        var partialCount = 0
        var emptyCount = 0
        var skippedCount = 0
        var failedCount = 0
        var wasCancelled = false
        var reservedOutputPaths = Set<String>()
        var inspectedInputBytes = 0

        for (position, item) in worklist.items.enumerated() {
            if Task.isCancelled || isCancelled?() == true { wasCancelled = true; break }
            progress?(position, worklist.items.count)
            let fileURL = item.url
            let source = SourceFileDescriptor(url: fileURL)
            logger.debug("Inspecting source input")

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

            var committedOutputURLs: [URL] = []
            do {
                if let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    guard size >= 0, size <= limits.totalWorkBytes - inspectedInputBytes else {
                        throw InputDiagnostic(code: "totalWorkLimitExceeded", stage: "intake", fileName: fileURL.lastPathComponent,
                                              summary: "Batch input exceeds the configured total-work byte limit.")
                    }
                    inspectedInputBytes += size
                }
            } catch {
                logFailure(error, stage: "intake")
                entries.append(ConversionEntry(fileName: source.reportBaseName, fileExtension: source.fileExtension,
                                               status: .failed, message: safeFailureMessage(error, stage: "intake"), outputURL: nil))
                failedCount += 1
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
                logFailure(error, stage: "probe")
                entries.append(ConversionEntry(fileName: source.reportBaseName, fileExtension: source.fileExtension, status: .failed, message: safeFailureMessage(error, stage: "probe"), outputURL: nil))
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
                var generatedOutputs: [GeneratedOutput] = []
                let appliedSettings: AppliedDelimitedSettings?
                var isEmpty = true
                var isPartial = false
                var extractorWarnings: [String] = []
                var capturedSettings: AppliedDelimitedSettings?
                for format in mode.formats {
                    let output: String
                    if let delimited = converter as? DelimitedTextConverter {
                        let result = try delimited.convert(at: fileURL, to: format, options: delimitedOptions)
                        output = result.output
                        capturedSettings = result.appliedSettings
                        isEmpty = isEmpty && result.isEmpty
                    } else {
                        let result = try converter.convertDetailed(at: fileURL, to: format)
                        output = result.output
                        isEmpty = isEmpty && result.quality == .empty
                        isPartial = isPartial || result.quality == .partial
                        for warning in result.warnings where !extractorWarnings.contains(warning) {
                            extractorWarnings.append(warning)
                        }
                    }
                    guard output.utf8.count <= limits.outputBytes else {
                        throw InputDiagnostic(code: "outputLimitExceeded", stage: "render", fileName: fileURL.lastPathComponent,
                                              summary: "Rendered output exceeds the configured byte limit.")
                    }
                    generatedOutputs.append(GeneratedOutput(format: format, payload: Data(output.utf8)))
                }
                appliedSettings = capturedSettings
                if Task.isCancelled || isCancelled?() == true { wasCancelled = true; break }

                var notes: [String] = []
                if bundleOriginal {
                    let bundlePlan = try outputBundleWriter.publish(generatedOutputs, withOriginal: fileURL, in: targetURL,
                                                                    reservedOutputPaths: reservedOutputPaths)
                    reservedOutputPaths.insert(normalizedPath(for: bundlePlan.url))
                    committedOutputURLs = [bundlePlan.url]
                    notes.append("Bundle contains the original and \(generatedOutputs.count) generated output\(generatedOutputs.count == 1 ? "" : "s").")
                    if bundlePlan.wasRenamed {
                        notes.append("Saved as \(bundlePlan.url.lastPathComponent) to avoid overwriting another item.")
                    }
                } else {
                    var plans: [OutputFilePlan] = []
                    for generated in generatedOutputs {
                        let plan = try outputWriter.publish(generated.payload, for: fileURL, in: targetURL,
                                                            outputExtension: generated.format.fileExtension,
                                                            reservedOutputPaths: reservedOutputPaths)
                        reservedOutputPaths.insert(normalizedPath(for: plan.url))
                        plans.append(plan)
                        committedOutputURLs.append(plan.url)
                    }
                    for plan in plans where plan.wasRenamed {
                        notes.append("Saved as \(plan.url.lastPathComponent) to avoid overwriting another file.")
                    }
                }
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
                        outputURLs: committedOutputURLs
                    )
                )
                if isPartial { partialCount += 1 } else if isEmpty { emptyCount += 1 } else { convertedCount += 1 }
            } catch OutputPublicationError.cancelled {
                if !committedOutputURLs.isEmpty {
                    entries.append(
                        ConversionEntry(fileName: source.reportBaseName, fileExtension: source.fileExtension,
                                        status: .partial,
                                        message: "Conversion was cancelled after \(committedOutputURLs.count) output was published.",
                                        outputURLs: committedOutputURLs)
                    )
                    partialCount += 1
                }
                wasCancelled = true
                break
            } catch {
                logFailure(error, stage: "convert")
                if !committedOutputURLs.isEmpty {
                    entries.append(
                        ConversionEntry(fileName: source.reportBaseName, fileExtension: source.fileExtension,
                                        status: .partial,
                                        message: "Published \(committedOutputURLs.count) output before another output failed. \(safeFailureMessage(error, stage: "convert"))",
                                        outputURLs: committedOutputURLs)
                    )
                    partialCount += 1
                    continue
                }
                entries.append(
                    ConversionEntry(
                        fileName: source.reportBaseName,
                        fileExtension: source.fileExtension,
                        status: .failed,
                        message: safeFailureMessage(error, stage: "convert"),
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

    private func logFailure(_ error: Error, stage: String) {
        let code = (error as? InputDiagnostic)?.code ?? (error as? DelimitedInputError)?.code ?? "conversionFailure"
        logger.error("File failed at \(stage, privacy: .public) with \(code, privacy: .public)")
    }

    private func safeFailureMessage(_ error: Error, stage: String) -> String {
        if error is InputDiagnostic || error is DelimitedInputError || error is ZipContainerError || error is PDFExtractionError ||
           error is ImageInputError || error is AttributedInputError {
            return error.localizedDescription
        }
        return InputDiagnostic(code: "conversionFailure", stage: stage,
                               summary: "Input could not be processed.", underlying: error).localizedDescription
    }
}
