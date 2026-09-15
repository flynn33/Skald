import Foundation

nonisolated enum BoundedInputReader {
    static func preflight(_ url: URL, maximumBytes: Int, maximumEntries: Int = 1_000) throws {
        guard maximumBytes > 0, maximumEntries > 0 else {
            throw InputDiagnostic(code: "invalidLimitConfiguration", stage: "configure", summary: "Input read limits must be positive.")
        }
        if Task.isCancelled { throw OutputPublicationError.cancelled }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        if values.isDirectory == true {
            var total = 0
            var entries = 0
            guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey], options: []) else {
                throw InputDiagnostic(code: "packageUnavailable", stage: "read", fileName: url.lastPathComponent,
                                      summary: "Package members could not be inspected.")
            }
            while let member = walker.nextObject() as? URL {
                if Task.isCancelled { throw OutputPublicationError.cancelled }
                entries += 1
                guard entries <= maximumEntries else { throw InputDiagnostic(code: "packageEntryLimitExceeded", stage: "read", fileName: url.lastPathComponent,
                                                                     summary: "Package has too many members.") }
                let memberValues = try member.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
                if memberValues.isSymbolicLink == true {
                    throw InputDiagnostic(code: "packageLinkDenied", stage: "read", fileName: url.lastPathComponent,
                                          summary: "Package links are not accepted.")
                }
                if memberValues.isRegularFile == true, let size = memberValues.fileSize {
                    guard size >= 0, size <= maximumBytes - total else {
                        throw InputDiagnostic(code: "inputLimitExceeded", stage: "read", fileName: url.lastPathComponent,
                                              summary: "Package exceeds the configured byte limit.")
                    }
                    total += size
                }
            }
        } else if let size = values.fileSize, size > maximumBytes {
            throw InputDiagnostic(code: "inputLimitExceeded", stage: "read", fileName: url.lastPathComponent,
                                  summary: "Input exceeds the configured byte limit.")
        }
    }

    static func read(_ url: URL, maximumBytes: Int, chunkBytes: Int = 64 * 1_024) throws -> Data {
        guard maximumBytes > 0, chunkBytes > 0 else {
            throw InputDiagnostic(code: "invalidLimitConfiguration", stage: "configure", summary: "Input read limits must be positive.")
        }
        try preflight(url, maximumBytes: maximumBytes)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while true {
            if Task.isCancelled { throw OutputPublicationError.cancelled }
            let remaining = maximumBytes - data.count
            let chunk = try handle.read(upToCount: min(chunkBytes, max(1, remaining))) ?? Data()
            if chunk.isEmpty { break }
            guard chunk.count <= maximumBytes - data.count else {
                throw InputDiagnostic(code: "inputLimitExceeded", stage: "read", fileName: url.lastPathComponent,
                                      summary: "Input exceeds the configured byte limit.")
            }
            data.append(chunk)
        }
        if Task.isCancelled { throw OutputPublicationError.cancelled }
        return data
    }
}
