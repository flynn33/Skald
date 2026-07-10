import Foundation

nonisolated struct OutputFilePlan: Sendable {
    let url: URL
    let wasRenamed: Bool
}

nonisolated protocol OutputFilePlanning: Sendable {
    func planOutput(
        for sourceURL: URL,
        in targetDirectoryURL: URL,
        outputExtension: String,
        reservedOutputPaths: Set<String>
    ) -> OutputFilePlan
}

nonisolated final class OutputFilePlanner: OutputFilePlanning, @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func planOutput(
        for sourceURL: URL,
        in targetDirectoryURL: URL,
        outputExtension: String,
        reservedOutputPaths: Set<String>
    ) -> OutputFilePlan {
        let source = SourceFileDescriptor(url: sourceURL)
        let preferredURL = makeURL(
            baseName: source.baseName,
            outputExtension: outputExtension,
            targetDirectoryURL: targetDirectoryURL
        )

        if isAvailable(preferredURL, sourceURL: sourceURL, reservedOutputPaths: reservedOutputPaths) {
            return OutputFilePlan(url: preferredURL, wasRenamed: false)
        }

        let qualifiedBaseName = source.fileExtension.isEmpty
            ? source.baseName
            : "\(source.baseName)-\(source.fileExtension)"
        var sequence = 1

        while true {
            let suffix = sequence == 1 ? "" : "-\(sequence)"
            let candidateURL = makeURL(
                baseName: qualifiedBaseName + suffix,
                outputExtension: outputExtension,
                targetDirectoryURL: targetDirectoryURL
            )

            if isAvailable(candidateURL, sourceURL: sourceURL, reservedOutputPaths: reservedOutputPaths) {
                return OutputFilePlan(url: candidateURL, wasRenamed: true)
            }

            sequence += 1
        }
    }

    private func makeURL(baseName: String, outputExtension: String, targetDirectoryURL: URL) -> URL {
        targetDirectoryURL
            .appendingPathComponent(baseName)
            .appendingPathExtension(outputExtension)
    }

    private func isAvailable(
        _ candidateURL: URL,
        sourceURL: URL,
        reservedOutputPaths: Set<String>
    ) -> Bool {
        let candidatePath = normalizedPath(for: candidateURL)
        let sourcePath = normalizedPath(for: sourceURL)

        guard candidatePath != sourcePath else {
            return false
        }

        guard !reservedOutputPaths.contains(candidatePath) else {
            return false
        }

        return !fileManager.fileExists(atPath: candidateURL.path)
    }

    private func normalizedPath(for url: URL) -> String {
        url.standardizedFileURL.path.lowercased()
    }
}
