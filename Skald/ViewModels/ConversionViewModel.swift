import Combine
import Foundation
import SwiftUI

@MainActor
final class ConversionViewModel: ObservableObject {
    enum Status: Equatable {
        case idle
        case converting
        case completed(hasFailures: Bool)
        case failed
    }

    @Published private(set) var sourceFolderURL: URL?
    @Published private(set) var targetFolderURL: URL?
    @Published var outputFormat: OutputFormat = .markdown
    @Published private(set) var statusMessage = "Choose source and target folders."
    @Published private(set) var status: Status = .idle
    @Published private(set) var report: ConversionReport?
    @Published private(set) var isConverting = false

    private let conversionManager: ConversionManager
    private let folderSelectionService: FolderSelecting

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
        sourceFolderURL != nil && targetFolderURL != nil && !isConverting
    }

    func selectSourceFolder() {
        if let url = folderSelectionService.selectFolder() {
            sourceFolderURL = url
            resetStatusAfterSelection()
        }
    }

    func selectTargetFolder() {
        if let url = folderSelectionService.selectFolder() {
            targetFolderURL = url
            resetStatusAfterSelection()
        }
    }

    func convertFiles() {
        guard let sourceFolderURL, let targetFolderURL else {
            return
        }

        let conversionManager = conversionManager
        let outputFormat = outputFormat
        isConverting = true
        report = nil
        status = .converting
        statusMessage = "Converting..."

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let report = try conversionManager.convertFiles(
                    in: sourceFolderURL,
                    to: targetFolderURL,
                    format: outputFormat
                )

                DispatchQueue.main.async {
                    self.finishConversion(with: report)
                }
            } catch {
                DispatchQueue.main.async {
                    self.failConversion(error)
                }
            }
        }
    }

    private func finishConversion(with report: ConversionReport) {
        self.report = report
        status = .completed(hasFailures: report.failedCount > 0)
        statusMessage = report.summaryLine
        isConverting = false
    }

    private func failConversion(_ error: Error) {
        status = .failed
        statusMessage = "Error: \(error.localizedDescription)"
        isConverting = false
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
