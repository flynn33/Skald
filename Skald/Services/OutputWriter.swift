import Darwin
import Foundation

nonisolated protocol OutputWriting {
    func publish(
        _ payload: Data,
        for sourceURL: URL,
        in targetDirectoryURL: URL,
        outputExtension: String,
        reservedOutputPaths: Set<String>
    ) throws -> OutputFilePlan
}

/// Publishes a complete same-directory temporary file with Darwin's exclusive rename.
/// Publication is atomic for visibility. fsync protects the temporary file's data;
/// the directory entry is not promised durable across sudden power loss.
nonisolated final class OutputWriter: OutputWriting {
    typealias WriteCall = (Int32, UnsafeRawPointer, Int) -> Int
    typealias RenameCall = (Int32, String, String) -> Int32

    private let planner: OutputFilePlanning
    private let writeCall: WriteCall
    private let renameCall: RenameCall
    private let beforeExclusiveRename: (URL) -> Void
    private let isCancelled: () -> Bool
    private let supportsExclusiveRenaming: (URL) -> Bool
    private let collisionLimit: Int

    init(
        planner: OutputFilePlanning = OutputFilePlanner(),
        collisionLimit: Int = 1_000,
        writeCall: @escaping WriteCall = { Darwin.write($0, $1, $2) },
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
        self.planner = planner
        self.collisionLimit = max(1, collisionLimit)
        self.writeCall = writeCall
        self.renameCall = renameCall
        self.beforeExclusiveRename = beforeExclusiveRename
        self.isCancelled = isCancelled
        self.supportsExclusiveRenaming = supportsExclusiveRenaming
    }

    func publish(
        _ payload: Data,
        for sourceURL: URL,
        in targetDirectoryURL: URL,
        outputExtension: String,
        reservedOutputPaths: Set<String>
    ) throws -> OutputFilePlan {
        if isCancelled() { throw OutputPublicationError.cancelled }
        let directoryFD = targetDirectoryURL.path.withCString {
            Darwin.open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard directoryFD >= 0 else { throw OutputPublicationError.invalidTarget }
        defer { _ = Darwin.close(directoryFD) }
        var directoryStat = stat()
        guard fstat(directoryFD, &directoryStat) == 0, (directoryStat.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
            throw OutputPublicationError.invalidTarget
        }
        guard supportsExclusiveRenaming(targetDirectoryURL) else {
            throw OutputPublicationError.exclusiveRenameUnsupported
        }

        var temporaryName = ""
        var temporaryFD: Int32 = -1
        for _ in 0..<8 {
            temporaryName = ".skald-\(UUID().uuidString).tmp"
            temporaryFD = temporaryName.withCString {
                Darwin.openat(directoryFD, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
            }
            if temporaryFD >= 0 { break }
            if errno != EEXIST { throw OutputPublicationError.io(stage: "temporary create", code: errno) }
        }
        guard temporaryFD >= 0 else { throw OutputPublicationError.collisionLimit }
        var temporaryStat = stat()
        guard fstat(temporaryFD, &temporaryStat) == 0 else {
            let code = errno
            _ = Darwin.close(temporaryFD)
            throw OutputPublicationError.io(stage: "temporary inspect", code: code)
        }
        var published = false
        defer {
            if temporaryFD >= 0 { _ = Darwin.close(temporaryFD) }
            if !published {
                var current = stat()
                let found = temporaryName.withCString {
                    fstatat(directoryFD, $0, &current, AT_SYMLINK_NOFOLLOW)
                }
                if found == 0, current.st_dev == temporaryStat.st_dev, current.st_ino == temporaryStat.st_ino {
                    _ = temporaryName.withCString { unlinkat(directoryFD, $0, 0) }
                }
            }
        }

        try writeFully(payload, to: temporaryFD)
        if isCancelled() { throw OutputPublicationError.cancelled }
        while fsync(temporaryFD) != 0 {
            if errno == EINTR { continue }
            throw OutputPublicationError.io(stage: "file flush", code: errno)
        }
        guard Darwin.close(temporaryFD) == 0 else {
            temporaryFD = -1
            throw OutputPublicationError.io(stage: "file close", code: errno)
        }
        temporaryFD = -1

        var reserved = reservedOutputPaths
        for _ in 0..<collisionLimit {
            if isCancelled() { throw OutputPublicationError.cancelled }
            try verifyDirectoryIdentity(targetDirectoryURL, directoryFD: directoryFD, expected: directoryStat)
            let plan = try planner.planOutput(
                for: sourceURL,
                in: targetDirectoryURL,
                outputExtension: outputExtension,
                reservedOutputPaths: reserved
            )
            guard plan.url.deletingLastPathComponent().standardizedFileURL.path == targetDirectoryURL.standardizedFileURL.path,
                  plan.url.lastPathComponent != ".", plan.url.lastPathComponent != ".." else {
                throw OutputPublicationError.invalidCandidate
            }
            guard plan.url.standardizedFileURL.path != sourceURL.standardizedFileURL.path else {
                throw OutputPublicationError.collisionLimit
            }
            if isCancelled() { throw OutputPublicationError.cancelled }
            beforeExclusiveRename(plan.url)
            try verifyDirectoryIdentity(targetDirectoryURL, directoryFD: directoryFD, expected: directoryStat)
            let result = renameCall(directoryFD, temporaryName, plan.url.lastPathComponent)
            if result == 0 {
                published = true
                return plan
            }
            let code = errno
            if code == EEXIST {
                reserved.insert(plan.url.standardizedFileURL.path.lowercased())
                continue
            }
            if code == ENOTSUP || code == EOPNOTSUPP || code == EINVAL || code == ENOSYS {
                throw OutputPublicationError.exclusiveRenameUnsupported
            }
            throw OutputPublicationError.io(stage: "exclusive rename", code: code)
        }
        throw OutputPublicationError.collisionLimit
    }

    private func writeFully(_ payload: Data, to descriptor: Int32) throws {
        try payload.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                if isCancelled() { throw OutputPublicationError.cancelled }
                let count = writeCall(descriptor, base.advanced(by: offset), bytes.count - offset)
                if count > 0, count <= bytes.count - offset { offset += count; continue }
                if count > bytes.count - offset { throw OutputPublicationError.io(stage: "payload write", code: EIO) }
                if count < 0 && errno == EINTR { continue }
                throw OutputPublicationError.io(stage: "payload write", code: count == 0 ? EIO : errno)
            }
        }
    }

    private func verifyDirectoryIdentity(_ directory: URL, directoryFD: Int32, expected: stat) throws {
        var current = stat()
        let result = directory.path.withCString { lstat($0, &current) }
        guard result == 0, current.st_dev == expected.st_dev, current.st_ino == expected.st_ino else {
            throw OutputPublicationError.targetChanged
        }
    }
}
