import Foundation

nonisolated final class ZipCollectionConverter: DocumentConverter {
    let supportedExtensions = ["zip"]
    private let memberConverters: [DocumentConverter]
    private let maximumInputBytes: Int
    private let maximumEntries: Int
    private let maximumExpandedBytes: Int
    private let maximumMemberBytes: Int
    private let maximumArchiveDepth: Int

    init(memberConverters: [DocumentConverter], maximumInputBytes: Int = 64 * 1_024 * 1_024,
         maximumEntries: Int = 1_000, maximumExpandedBytes: Int = 256 * 1_024 * 1_024,
         maximumMemberBytes: Int = 64 * 1_024 * 1_024, maximumArchiveDepth: Int = 2) {
        self.memberConverters = memberConverters
        self.maximumInputBytes = maximumInputBytes
        self.maximumEntries = maximumEntries
        self.maximumExpandedBytes = maximumExpandedBytes
        self.maximumMemberBytes = maximumMemberBytes
        self.maximumArchiveDepth = maximumArchiveDepth
    }

    func convert(at url: URL, to format: OutputFormat) throws -> String {
        try convertDetailed(at: url, to: format).output
    }

    func convertDetailed(at url: URL, to format: OutputFormat) throws -> ConverterOutcome {
        let bytes = try BoundedInputReader.read(url, maximumBytes: maximumInputBytes)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("Skald-ZIP-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: temporary) }
        var rows: [[String: Any]] = []
        var markdown: [String] = ["# ZIP collection", ""]
        var totalEntries = 0
        var totalExpanded = 0
        var hasPartial = false
        var hasContent = false

        func record(path: String, depth: Int, status: String, message: String? = nil, content: Any? = nil,
                    body: String? = nil, warnings: [String] = []) {
            var row: [String: Any] = ["path": path, "archiveDepth": depth, "status": status]
            if let message { row["message"] = message }
            if let content { row["content"] = content }
            if !warnings.isEmpty { row["warnings"] = warnings }
            rows.append(row)
            markdown.append("## Member \(rows.count)")
            markdown.append("")
            let pathObject: [String: Any] = ["path": path, "archiveDepth": depth, "status": status]
            if let encoded = try? JSONSerialization.data(withJSONObject: pathObject, options: [.sortedKeys, .withoutEscapingSlashes]),
               let line = String(data: encoded, encoding: .utf8) {
                markdown += ["~~~json", line, "~~~", ""]
            }
            if let message { markdown += ["_\(message)_", ""] }
            if let body { markdown += [body.trimmingCharacters(in: .whitespacesAndNewlines), ""] }
        }

        func walk(_ archiveBytes: Data, prefix: String, depth: Int) throws {
            guard depth <= maximumArchiveDepth else {
                throw ZipContainerError(code: "archiveDepthLimitExceeded", summary: "Nested ZIP depth exceeds the configured limit.")
            }
            let archive = try SafeZipArchive(data: archiveBytes, maximumEntries: maximumEntries,
                                             maximumExpandedBytes: maximumExpandedBytes,
                                             maximumMemberBytes: maximumMemberBytes)
            for entry in archive.entries {
                if Task.isCancelled { throw OutputPublicationError.cancelled }
                totalEntries += 1
                guard totalEntries <= maximumEntries, entry.expandedSize <= maximumExpandedBytes - totalExpanded else {
                    throw ZipContainerError(code: "archiveExpansionLimitExceeded", summary: "Nested ZIP collection exceeds entry or expanded-byte limits.")
                }
                totalExpanded += entry.expandedSize
                let path = prefix + entry.path
                if entry.isDirectory {
                    record(path: path, depth: depth, status: "skipped", message: "Directory member.")
                    hasPartial = true
                    continue
                }
                let data = try archive.extract(entry)
                let fileExtension = URL(fileURLWithPath: entry.path).pathExtension.lowercased()
                if fileExtension == "zip" {
                    if depth == maximumArchiveDepth {
                        record(path: path, depth: depth, status: "failed", message: "archiveDepthLimitExceeded: Nested ZIP depth exceeds the configured limit.")
                        hasPartial = true
                    } else {
                        try walk(data, prefix: path + "!/", depth: depth + 1)
                    }
                    continue
                }
                let basename = URL(fileURLWithPath: entry.path).lastPathComponent
                let memberURL = temporary.appendingPathComponent("member-\(totalEntries)-\(basename)")
                try data.write(to: memberURL, options: .withoutOverwriting)
                defer { try? FileManager.default.removeItem(at: memberURL) }
                var converter = memberConverters.first { $0.supportedExtensions.contains(fileExtension) }
                do {
                    let inspection = try ContentProbe().inspect(memberURL, fileExtension: fileExtension,
                                                                 knownExtension: converter != nil)
                    switch inspection {
                    case .compatible: break
                    case .strictText: converter = memberConverters.first { $0 is TextConverter }
                    case .binary:
                        record(path: path, depth: depth, status: "skipped", message: "Unknown binary member.")
                        hasPartial = true
                        continue
                    case .extensionConflict:
                        record(path: path, depth: depth, status: "failed", message: "extensionContentMismatch: Member extension conflicts with content.")
                        hasPartial = true
                        continue
                    }
                    guard let converter else {
                        record(path: path, depth: depth, status: "skipped", message: "Unsupported member type.")
                        hasPartial = true
                        continue
                    }
                    let outcome = try converter.convertDetailed(at: memberURL, to: format)
                    let status = outcome.quality == .partial ? "partial" : (outcome.quality == .empty ? "empty" : "converted")
                    hasContent = hasContent || status == "converted" || status == "partial"
                    hasPartial = hasPartial || status == "partial"
                    let jsonContent: Any?
                    if format == .json {
                        jsonContent = try JSONSerialization.jsonObject(with: Data(outcome.output.utf8))
                    } else { jsonContent = nil }
                    record(path: path, depth: depth, status: status, content: jsonContent,
                           body: format == .markdown ? outcome.output : nil, warnings: outcome.warnings)
                } catch OutputPublicationError.cancelled {
                    throw OutputPublicationError.cancelled
                } catch {
                    let code = (error as? InputDiagnostic)?.code ?? (error as? DelimitedInputError)?.code ??
                               (error as? ZipContainerError)?.code ?? "memberConversionFailed"
                    record(path: path, depth: depth, status: "failed", message: "\(code): Member could not be converted.")
                    hasPartial = true
                }
            }
        }
        try walk(bytes, prefix: url.lastPathComponent + "!/", depth: 1)
        let quality: ExtractionQuality = hasPartial ? .partial : (hasContent ? .complete : .empty)
        let output: String
        switch format {
        case .markdown:
            output = markdown.joined(separator: "\n") + "\n"
        case .json:
            let document: [String: Any] = [
                "version": "2.0", "source": ["fileName": url.lastPathComponent, "fileExtension": "zip"],
                "summary": ["memberCount": rows.count, "extractionStatus": hasPartial ? "partial" : (hasContent ? "complete" : "empty")],
                "members": rows
            ]
            let encoded = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            output = String(decoding: encoded, as: UTF8.self) + "\n"
        }
        return ConverterOutcome(output: output, quality: quality, warnings: hasPartial ? ["collectionPartial"] : [])
    }
}
