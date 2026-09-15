import Combine
import Foundation
import SwiftUI

@MainActor
final class ConversionViewModel: ObservableObject {
    enum Status: Equatable {
        case idle
        case converting
        case completed(hasFailures: Bool)
        case cancelled
        case failed
    }

    @Published private(set) var sourceFolderURL: URL?
    @Published private(set) var sourceURLs: [URL] = []
    @Published private(set) var targetFolderURL: URL?
    @Published var outputFormat: OutputFormat = .markdown
    @Published var textEncoding: TextEncodingChoice = .automatic
    @Published var delimiterChoice: DelimiterChoice = .automatic
    @Published var headerMode: HeaderMode = .automatic
    @Published var usesCustomDelimiter = false
    @Published var customDelimiter = ""
    @Published var allowsSepPreamble = false
    @Published var recursive = false
    @Published var includeHidden = false
    @Published private(set) var progressCount = 0
    @Published private(set) var progressTotal = 0
    @Published private(set) var statusMessage = "Choose sources and a target folder."
    @Published private(set) var status: Status = .idle
    @Published private(set) var report: ConversionReport?
    @Published private(set) var isConverting = false

    private let conversionManager: ConversionManager
    private let folderSelectionService: FolderSelecting
    private var conversionTask: Task<Void, Never>?

    convenience init() {
        self.init(
            conversionManager: ConversionManager(),
            folderSelectionService: FolderSelectionService()
        )
    }

    init(conversionManager: ConversionManager, folderSelectionService: FolderSelecting) {
        self.conversionManager = conversionManager
        self.folderSelectionService = folderSelectionService
    }

    var canConvert: Bool {
        !sourceURLs.isEmpty && targetFolderURL != nil && !isConverting
    }

    func selectSourceFolder() {
        let selected = folderSelectionService.selectSources()
        if !selected.isEmpty {
            acceptDroppedSources(selected)
            resetStatusAfterSelection()
        }
    }

    func acceptDroppedSources(_ urls: [URL]) {
        guard !isConverting else { return }
        sourceURLs = urls
        sourceFolderURL = urls.first
        resetStatusAfterSelection()
    }

    func selectTargetFolder() {
        if let url = folderSelectionService.selectFolder() {
            targetFolderURL = url
            resetStatusAfterSelection()
        }
    }

    func convertFiles() {
        guard !sourceURLs.isEmpty, let targetFolderURL, !isConverting else {
            return
        }

        let conversionManager = conversionManager
        let outputFormat = outputFormat
        let selections = sourceURLs
        let intakeOptions = IntakeOptions(recursive: recursive, includeHidden: includeHidden)
        let delimitedOptions = DelimitedOptions(
            encoding: textEncoding,
            delimiter: usesCustomDelimiter ? .custom(customDelimiter) : delimiterChoice,
            header: headerMode,
            allowSepPreamble: allowsSepPreamble
        )
        isConverting = true
        report = nil
        status = .converting
        statusMessage = "Preparing input worklist..."
        progressCount = 0
        progressTotal = 0

        conversionTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let report = try conversionManager.convertSelections(
                    selections,
                    to: targetFolderURL,
                    format: outputFormat,
                    delimitedOptions: delimitedOptions,
                    intakeOptions: intakeOptions,
                    progress: { completed, total in
                        Task { @MainActor [weak self] in
                            self?.updateProgress(completed: completed, total: total)
                        }
                    }
                )
                await self?.finishConversion(with: report)
            } catch {
                await self?.failConversion(error)
            }
        }
    }

    func cancelConversion() {
        guard isConverting else { return }
        conversionTask?.cancel()
        statusMessage = "Cancelling..."
    }

    private func updateProgress(completed: Int, total: Int) {
        guard isConverting else { return }
        progressCount = completed
        progressTotal = total
        statusMessage = "Converting \(completed) of \(total) inputs..."
    }

    private func finishConversion(with report: ConversionReport) {
        self.report = report
        status = report.wasCancelled ? .cancelled : .completed(hasFailures: report.failedCount > 0)
        statusMessage = report.summaryLine
        isConverting = false
        conversionTask = nil
    }

    private func failConversion(_ error: Error) {
        status = .failed
        statusMessage = "Error: \(error.localizedDescription)"
        isConverting = false
        conversionTask = nil
    }

    private func resetStatusAfterSelection() {
        guard !isConverting else {
            return
        }

        if canConvert {
            status = .idle
            statusMessage = "Ready to convert."
        }
    }
}
