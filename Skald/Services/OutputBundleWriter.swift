import Darwin
import Foundation

nonisolated struct GeneratedOutput: Sendable {
    let format: OutputFormat
    let payload: Data
}

nonisolated struct OutputBundlePlan: Sendable {
    let url: URL
    let originalURL: URL
    let generatedURLs: [URL]
    let wasRenamed: Bool
}

nonisolated protocol OutputBundleWriting: Sendable {
    func publish(
        _ outputs: [GeneratedOutput],
        withOriginal sourceURL: URL,
        in targetDirectoryURL: URL,
        reservedOutputPaths: Set<String>
    ) throws -> OutputBundlePlan
}

/// Stages one source and all rendered outputs in a private same-directory folder,
/// then publishes the complete folder with an exclusive rename.
nonisolated final class OutputBundleWriter: OutputBundleWriting, @unchecked Sendable {
    typealias RenameCall = (Int32, String, String) -> Int32

    private let fileManager: FileManager
    private let renameCall: RenameCall
    private let beforeExclusiveRename: (URL) -> Void
    private let isCancelled: () -> Bool
    private let supportsExclusiveRenaming: (URL) -> Bool
    private let collisionLimit: Int

    init(
        fileManager: FileManager = .default,
        collisionLimit: Int = 1_000,
        renameCall: @escaping RenameCall = { directoryFD, oldName, newName in
            oldName.withCString { old in
                newName.withCString { new in
                    renameatx_np(directoryFD, old, directoryFD, new, UInt32(RENAME_EXCL))
                }
            }
        },
        beforeExclusiveRename: @escaping (URL) -> Void = { _ in },
        isCancelled: @escaping () -> Bool = { Task.isCancelled },
        supportsExclusiveRenaming: @escaping (URL) -> Bool = {
            (try? $0.resourceValues(forKeys: [.volumeSupportsExclusiveRenamingKey]).volumeSupportsExclusiveRenaming) == true
        }
    ) {
        self.fileManager = fileManager
        self.collisionLimit = max(1, collisionLimit)
        self.renameCall = renameCall
        self.beforeExclusiveRename = beforeExclusiveRename
        self.isCancelled = isCancelled
        self.supportsExclusiveRenaming = supportsExclusiveRenaming
    }

    func publish(
        _ outputs: [GeneratedOutput],
        withOriginal sourceURL: URL,
        in targetDirectoryURL: URL,
        reservedOutputPaths: Set<String>
    ) throws -> OutputBundlePlan {
        guard !outputs.isEmpty else { throw OutputPublicationError.invalidCandidate }
        if isCancelled() { throw OutputPublicationError.cancelled }

        let directoryFD = targetDirectoryURL.path.withCString {
            Darwin.open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard directoryFD >= 0 else { throw OutputPublicationError.invalidTarget }
        defer { _ = Darwin.close(directoryFD) }

        var directoryStat = stat()
        guard fstat(directoryFD, &directoryStat) == 0,
              (directoryStat.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
            throw OutputPublicationError.invalidTarget
        }
        guard supportsExclusiveRenaming(targetDirectoryURL) else {
            throw OutputPublicationError.exclusiveRenameUnsupported
        }

        let temporaryName = try createTemporaryDirectory(in: directoryFD)
        let temporaryURL = targetDirectoryURL.appendingPathComponent(temporaryName, isDirectory: true)
        var temporaryStat = stat()
        let inspected = temporaryName.withCString {
            fstatat(directoryFD, $0, &temporaryStat, AT_SYMLINK_NOFOLLOW)
        }
        guard inspected == 0 else {
            try? fileManager.removeItem(at: temporaryURL)
            throw OutputPublicationError.io(stage: "bundle temporary inspect", code: errno)
        }
        var published = false
        defer {
            if !published {
                var current = stat()
                let found = temporaryName.withCString {
                    fstatat(directoryFD, $0, &current, AT_SYMLINK_NOFOLLOW)
                }
                if found == 0,
                   current.st_dev == temporaryStat.st_dev,
                   current.st_ino == temporaryStat.st_ino {
                    removeOwnedDirectory(named: temporaryName, from: directoryFD)
                }
            }
        }

        let originalName = sourceURL.lastPathComponent
        guard !originalName.isEmpty, originalName != ".", originalName != ".." else {
            throw OutputPublicationError.invalidCandidate
        }
        let stagedOriginalURL = temporaryURL.appendingPathComponent(originalName)
        try fileManager.copyItem(at: sourceURL, to: stagedOriginalURL)

        var occupiedNames = Set([originalName.lowercased()])
        var generatedNames: [String] = []
        let source = SourceFileDescriptor(url: sourceURL)
        for output in outputs {
            if isCancelled() { throw OutputPublicationError.cancelled }
            let name = try generatedName(baseName: source.baseName, extension: output.format.fileExtension,
                                         occupiedNames: &occupiedNames)
            let stagedURL = temporaryURL.appendingPathComponent(name)
            try output.payload.write(to: stagedURL, options: .withoutOverwriting)
            guard chmod(stagedURL.path, mode_t(0o600)) == 0 else {
                throw OutputPublicationError.io(stage: "bundle output permissions", code: errno)
            }
            try flushFile(at: stagedURL)
            generatedNames.append(name)
        }

        var reserved = reservedOutputPaths
        for sequence in 0..<collisionLimit {
            if isCancelled() { throw OutputPublicationError.cancelled }
            try verifyDirectoryIdentity(targetDirectoryURL, expected: directoryStat)
            let candidateName = bundleName(for: source, sequence: sequence)
            let candidateURL = targetDirectoryURL.appendingPathComponent(candidateName, isDirectory: true)
            let candidatePath = normalizedPath(for: candidateURL)
            if reserved.contains(candidatePath) || pathEntryExists(named: candidateName, in: directoryFD) {
                reserved.insert(candidatePath)
                continue
            }
            beforeExclusiveRename(candidateURL)
            try verifyDirectoryIdentity(targetDirectoryURL, expected: directoryStat)
            let result = renameCall(directoryFD, temporaryName, candidateName)
            if result == 0 {
                published = true
                return OutputBundlePlan(
                    url: candidateURL,
                    originalURL: candidateURL.appendingPathComponent(originalName),
                    generatedURLs: generatedNames.map { candidateURL.appendingPathComponent($0) },
                    wasRenamed: sequence > 0
                )
            }
            let code = errno
            if code == EEXIST {
                reserved.insert(candidatePath)
                continue
            }
            if code == ENOTSUP || code == EOPNOTSUPP || code == EINVAL || code == ENOSYS {
                throw OutputPublicationError.exclusiveRenameUnsupported
            }
            throw OutputPublicationError.io(stage: "bundle exclusive rename", code: code)
        }
        throw OutputPublicationError.collisionLimit
    }

    private func createTemporaryDirectory(in directoryFD: Int32) throws -> String {
        for _ in 0..<8 {
            let name = ".skald-\(UUID().uuidString).bundle-tmp"
            let result = name.withCString { mkdirat(directoryFD, $0, mode_t(0o700)) }
            if result == 0 { return name }
            if errno != EEXIST {
                throw OutputPublicationError.io(stage: "bundle temporary create", code: errno)
            }
        }
        throw OutputPublicationError.collisionLimit
    }

    private func generatedName(baseName: String, extension fileExtension: String,
                               occupiedNames: inout Set<String>) throws -> String {
        for sequence in 0..<collisionLimit {
            let suffix = sequence == 0 ? "" : (sequence == 1 ? "-converted" : "-converted-\(sequence)")
            let candidate = "\(baseName)\(suffix).\(fileExtension)"
            if occupiedNames.insert(candidate.lowercased()).inserted { return candidate }
        }
        throw OutputPublicationError.collisionLimit
    }

    private func bundleName(for source: SourceFileDescriptor, sequence: Int) -> String {
        if sequence == 0 { return "\(source.baseName)-bundle" }
        let qualified = source.fileExtension.isEmpty ? source.baseName : "\(source.baseName)-\(source.fileExtension)"
        return sequence == 1 ? "\(qualified)-bundle" : "\(qualified)-bundle-\(sequence)"
    }

    private func pathEntryExists(named name: String, in directoryFD: Int32) -> Bool {
        var info = stat()
        return name.withCString { fstatat(directoryFD, $0, &info, AT_SYMLINK_NOFOLLOW) } == 0
    }

    private func normalizedPath(for url: URL) -> String {
        url.standardizedFileURL.path.lowercased()
    }

    private func flushFile(at url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw OutputPublicationError.io(stage: "bundle output open", code: errno) }
        defer { _ = Darwin.close(descriptor) }
        while fsync(descriptor) != 0 {
            if errno == EINTR { continue }
            throw OutputPublicationError.io(stage: "bundle output flush", code: errno)
        }
    }

    private func verifyDirectoryIdentity(_ directory: URL, expected: stat) throws {
        var current = stat()
        guard lstat(directory.path, &current) == 0,
              current.st_dev == expected.st_dev,
              current.st_ino == expected.st_ino else {
            throw OutputPublicationError.targetChanged
        }
    }

    private func removeOwnedDirectory(named name: String, from parentFD: Int32) {
        let directoryFD = name.withCString {
            openat(parentFD, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard directoryFD >= 0 else { return }
        removeContents(of: directoryFD)
        _ = Darwin.close(directoryFD)
        _ = name.withCString { unlinkat(parentFD, $0, AT_REMOVEDIR) }
    }

    private func removeContents(of directoryFD: Int32) {
        let duplicateFD = dup(directoryFD)
        guard duplicateFD >= 0, let stream = fdopendir(duplicateFD) else {
            if duplicateFD >= 0 { _ = Darwin.close(duplicateFD) }
            return
        }
        defer { closedir(stream) }

        while let entry = readdir(stream) {
            var nameBuffer = entry.pointee.d_name
            let name = withUnsafePointer(to: &nameBuffer) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                    String(cString: $0)
                }
            }
            if name == "." || name == ".." { continue }

            var info = stat()
            let inspected = name.withCString {
                fstatat(directoryFD, $0, &info, AT_SYMLINK_NOFOLLOW)
            }
            guard inspected == 0 else { continue }
            if (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) {
                let childFD = name.withCString {
                    openat(directoryFD, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
                }
                if childFD >= 0 {
                    removeContents(of: childFD)
                    _ = Darwin.close(childFD)
                    _ = name.withCString { unlinkat(directoryFD, $0, AT_REMOVEDIR) }
                }
            } else {
                _ = name.withCString { unlinkat(directoryFD, $0, 0) }
            }
        }
    }
}
