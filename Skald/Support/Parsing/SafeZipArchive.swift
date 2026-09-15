import Foundation
import zlib

nonisolated struct ZipContainerError: Error, LocalizedError {
    let code: String
    let summary: String
    var errorDescription: String? { "\(code): \(summary)" }
}

nonisolated struct SafeZipEntry {
    let path: String
    let method: UInt16
    let flags: UInt16
    let compressedSize: Int
    let expandedSize: Int
    let crc: UInt32
    let localOffset: Int
    let isDirectory: Bool
}

/// ZIP32 stored/deflated package reader. The central directory is validated
/// before any member is decompressed or written to a temporary file.
nonisolated final class SafeZipArchive {
    let entries: [SafeZipEntry]
    private let data: Data
    private let maximumMemberBytes: Int

    init(data: Data, maximumEntries: Int = 1_000, maximumExpandedBytes: Int = 256 * 1_024 * 1_024,
         maximumMemberBytes: Int = 64 * 1_024 * 1_024) throws {
        let data = data.startIndex == 0 ? data : Data(data)
        guard maximumEntries > 0, maximumExpandedBytes > 0, maximumMemberBytes > 0 else {
            throw ZipContainerError(code: "invalidLimitConfiguration", summary: "Archive limits must be positive.")
        }
        self.data = data
        self.maximumMemberBytes = maximumMemberBytes
        guard data.count >= 22 else { throw ZipContainerError(code: "invalidZIP", summary: "ZIP end directory is missing.") }
        let start = max(0, data.count - 22 - 65_535)
        guard let end = stride(from: data.count - 22, through: start, by: -1).first(where: { position in
            data[position] == 0x50 && data[position + 1] == 0x4B && data[position + 2] == 0x05 && data[position + 3] == 0x06 &&
            Int(Self.u16(data, position + 20)) + position + 22 == data.count
        }) else { throw ZipContainerError(code: "invalidZIP", summary: "ZIP end directory is missing or has trailing bytes.") }
        let disks = Self.u16(data, end + 4)
        let directoryDisk = Self.u16(data, end + 6)
        let diskEntries = Int(Self.u16(data, end + 8))
        let count = Int(Self.u16(data, end + 10))
        guard count != 0xFFFF else {
            throw ZipContainerError(code: "zip64Unsupported", summary: "ZIP64 packages are not in the supported subset.")
        }
        guard disks == 0, directoryDisk == 0, diskEntries == count else {
            throw ZipContainerError(code: "multiDiskZIPUnsupported", summary: "Multi-disk ZIP packages are not accepted.")
        }
        guard count <= maximumEntries else { throw ZipContainerError(code: "archiveEntryLimitExceeded", summary: "Archive has too many members.") }
        let directorySize = Int(Self.u32(data, end + 12))
        let directoryOffset = Int(Self.u32(data, end + 16))
        guard directorySize != Int(UInt32.max), directoryOffset != Int(UInt32.max) else {
            throw ZipContainerError(code: "zip64Unsupported", summary: "ZIP64 packages are not in the supported subset.")
        }
        guard directoryOffset <= end, directorySize <= end - directoryOffset,
              directoryOffset + directorySize == end else {
            throw ZipContainerError(code: "invalidZIP", summary: "ZIP central directory has invalid bounds.")
        }
        var parsed: [SafeZipEntry] = []
        parsed.reserveCapacity(count)
        var seenPaths = Set<String>()
        var filePaths = Set<String>()
        var directoryPaths = Set<String>()
        var seenOffsets = Set<Int>()
        var expandedTotal = 0
        var cursor = directoryOffset
        for _ in 0..<count {
            if Task.isCancelled { throw OutputPublicationError.cancelled }
            guard cursor + 46 <= end, Self.u32(data, cursor) == 0x02014B50 else {
                throw ZipContainerError(code: "invalidZIP", summary: "ZIP central member header is malformed.")
            }
            let flags = Self.u16(data, cursor + 8)
            let method = Self.u16(data, cursor + 10)
            let crc = Self.u32(data, cursor + 16)
            let compressed = Int(Self.u32(data, cursor + 20))
            let expanded = Int(Self.u32(data, cursor + 24))
            let nameLength = Int(Self.u16(data, cursor + 28))
            let extraLength = Int(Self.u16(data, cursor + 30))
            let commentLength = Int(Self.u16(data, cursor + 32))
            let externalAttributes = Self.u32(data, cursor + 38)
            let localOffset = Int(Self.u32(data, cursor + 42))
            guard nameLength > 0, nameLength <= 1_024, nameLength + extraLength + commentLength <= end - cursor - 46 else {
                throw ZipContainerError(code: "invalidZIP", summary: "ZIP member metadata is out of bounds.")
            }
            guard flags & 0x0001 == 0, flags & 0x0040 == 0 else {
                throw ZipContainerError(code: "encryptedZIPUnsupported", summary: "Encrypted ZIP members require a password and are not imported.")
            }
            guard flags & ~UInt16(0x0808) == 0 else {
                throw ZipContainerError(code: "zipVariantUnsupported", summary: "ZIP member uses unsupported flags.")
            }
            guard method == 0 || method == 8 else {
                throw ZipContainerError(code: "zipMethodUnsupported", summary: "ZIP member compression method is unsupported.")
            }
            guard compressed != Int(UInt32.max), expanded != Int(UInt32.max), localOffset != Int(UInt32.max) else {
                throw ZipContainerError(code: "zip64Unsupported", summary: "ZIP64 members are not in the supported subset.")
            }
            let nameBytes = data[(cursor + 46)..<(cursor + 46 + nameLength)]
            guard let name = String(data: nameBytes, encoding: .utf8) else {
                throw ZipContainerError(code: "zipNameEncodingUnsupported", summary: "ZIP member name is not UTF-8.")
            }
            let path = try Self.validatePath(name)
            let collisionKey = path.precomposedStringWithCanonicalMapping.lowercased()
            guard seenPaths.insert(collisionKey).inserted else {
                throw ZipContainerError(code: "archivePathCollision", summary: "Archive contains colliding member paths.")
            }
            guard seenOffsets.insert(localOffset).inserted else {
                throw ZipContainerError(code: "archiveOffsetCollision", summary: "Archive members reuse one local header.")
            }
            let unixMode = UInt16(externalAttributes >> 16)
            let kind = unixMode & 0xF000
            guard kind == 0 || kind == 0x8000 || kind == 0x4000 else {
                throw ZipContainerError(code: "archiveLinkDenied", summary: "Archive links and special members are not accepted.")
            }
            let directory = path.hasSuffix("/") || kind == 0x4000
            let comparable = collisionKey.hasSuffix("/") ? String(collisionKey.dropLast()) : collisionKey
            if directory { directoryPaths.insert(comparable) }
            else { filePaths.insert(comparable) }
            guard expanded <= maximumMemberBytes, expanded <= maximumExpandedBytes - expandedTotal else {
                throw ZipContainerError(code: "archiveExpansionLimitExceeded", summary: "Archive expanded bytes exceed the configured limit.")
            }
            if expanded > 0, (compressed == 0 || expanded > compressed * 100) {
                throw ZipContainerError(code: "archiveExpansionRatioExceeded", summary: "Archive member expansion ratio exceeds the configured safety ceiling.")
            }
            if method == 0, compressed != expanded {
                throw ZipContainerError(code: "invalidZIP", summary: "Stored ZIP member sizes disagree.")
            }
            expandedTotal += expanded
            parsed.append(SafeZipEntry(path: path, method: method, flags: flags, compressedSize: compressed,
                                       expandedSize: expanded, crc: crc, localOffset: localOffset, isDirectory: directory))
            cursor += 46 + nameLength + extraLength + commentLength
        }
        guard cursor == end else { throw ZipContainerError(code: "invalidZIP", summary: "ZIP central directory has unexplained bytes.") }
        for path in filePaths {
            guard !directoryPaths.contains(path),
                  !filePaths.contains(where: { $0.hasPrefix(path + "/") }),
                  !directoryPaths.contains(where: { $0.hasPrefix(path + "/") }) else {
                throw ZipContainerError(code: "archivePathCollision", summary: "Archive file and directory paths collide.")
            }
        }
        var localRanges: [Range<Int>] = []
        for entry in parsed {
            localRanges.append(try Self.localRange(data, entry: entry, before: directoryOffset))
        }
        localRanges.sort { $0.lowerBound < $1.lowerBound }
        if localRanges.count > 1 {
            for index in 1..<localRanges.count {
                guard localRanges[index - 1].upperBound <= localRanges[index].lowerBound else {
                    throw ZipContainerError(code: "archiveOffsetCollision", summary: "ZIP local member ranges overlap.")
                }
            }
        }
        entries = parsed
    }

    private static func localRange(_ data: Data, entry: SafeZipEntry, before directory: Int) throws -> Range<Int> {
        let offset = entry.localOffset
        guard offset <= directory - 30, u32(data, offset) == 0x04034B50,
              u16(data, offset + 6) == entry.flags, u16(data, offset + 8) == entry.method else {
            throw ZipContainerError(code: "invalidZIP", summary: "ZIP local header disagrees with the central directory.")
        }
        let nameLength = Int(u16(data, offset + 26))
        let extraLength = Int(u16(data, offset + 28))
        guard nameLength > 0, nameLength + extraLength <= directory - offset - 30,
              String(data: data[(offset + 30)..<(offset + 30 + nameLength)], encoding: .utf8) == entry.path else {
            throw ZipContainerError(code: "invalidZIP", summary: "ZIP local member name or metadata is invalid.")
        }
        if entry.flags & 0x0008 == 0 {
            guard u32(data, offset + 14) == entry.crc,
                  Int(u32(data, offset + 18)) == entry.compressedSize,
                  Int(u32(data, offset + 22)) == entry.expandedSize else {
                throw ZipContainerError(code: "invalidZIP", summary: "ZIP local and central member sizes or checksum disagree.")
            }
        }
        let begin = offset + 30 + nameLength + extraLength
        guard entry.compressedSize <= directory - begin else {
            throw ZipContainerError(code: "invalidZIP", summary: "ZIP member data overlaps the central directory.")
        }
        return offset..<(begin + entry.compressedSize)
    }

    func extract(_ entry: SafeZipEntry) throws -> Data {
        if Task.isCancelled { throw OutputPublicationError.cancelled }
        let offset = entry.localOffset
        guard offset <= data.count - 30, Self.u32(data, offset) == 0x04034B50 else {
            throw ZipContainerError(code: "invalidZIP", summary: "ZIP local member header is malformed.")
        }
        guard Self.u16(data, offset + 6) == entry.flags, Self.u16(data, offset + 8) == entry.method else {
            throw ZipContainerError(code: "invalidZIP", summary: "ZIP local and central member headers disagree.")
        }
        let nameLength = Int(Self.u16(data, offset + 26))
        let extraLength = Int(Self.u16(data, offset + 28))
        guard nameLength > 0, nameLength + extraLength <= data.count - offset - 30 else {
            throw ZipContainerError(code: "invalidZIP", summary: "ZIP local member metadata is out of bounds.")
        }
        guard String(data: data[(offset + 30)..<(offset + 30 + nameLength)], encoding: .utf8) == entry.path else {
            throw ZipContainerError(code: "invalidZIP", summary: "ZIP local and central member names disagree.")
        }
        let begin = offset + 30 + nameLength + extraLength
        guard begin <= data.count, entry.compressedSize <= data.count - begin else {
            throw ZipContainerError(code: "invalidZIP", summary: "ZIP member data is out of bounds.")
        }
        let result: Data
        if entry.method == 0 {
            result = data[begin..<(begin + entry.compressedSize)]
        } else {
            result = try inflateMember(begin: begin, compressed: entry.compressedSize, expanded: entry.expandedSize)
        }
        guard result.count == entry.expandedSize else {
            throw ZipContainerError(code: "invalidZIP", summary: "ZIP expanded member length disagrees with metadata.")
        }
        let checksum: UInt32 = result.withUnsafeBytes { bytes in
            UInt32(zlib.crc32(0, bytes.bindMemory(to: Bytef.self).baseAddress, uInt(bytes.count)))
        }
        guard checksum == entry.crc else { throw ZipContainerError(code: "zipChecksumMismatch", summary: "ZIP member checksum failed.") }
        return result
    }

    private func inflateMember(begin: Int, compressed: Int, expanded: Int) throws -> Data {
        var stream = z_stream()
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw ZipContainerError(code: "zipInflateFailed", summary: "ZIP deflate decoder could not start.")
        }
        defer { inflateEnd(&stream) }
        var output = Data()
        try data.withUnsafeBytes { source in
            let input = source.bindMemory(to: Bytef.self)
            stream.next_in = UnsafeMutablePointer(mutating: input.baseAddress!.advanced(by: begin))
            stream.avail_in = uInt(compressed)
            while true {
                if Task.isCancelled { throw OutputPublicationError.cancelled }
                let consumedBefore = stream.total_in
                var chunk = Data(count: 64 * 1_024)
                let status: Int32 = chunk.withUnsafeMutableBytes { destination in
                    stream.next_out = destination.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(destination.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                let produced = chunk.count - Int(stream.avail_out)
                guard produced <= expanded - output.count else {
                    throw ZipContainerError(code: "archiveExpansionLimitExceeded", summary: "ZIP member expanded beyond its declared size.")
                }
                output.append(chunk.prefix(produced))
                if status == Z_STREAM_END { break }
                guard status == Z_OK, produced > 0 || stream.total_in > consumedBefore else {
                    throw ZipContainerError(code: "zipInflateFailed", summary: "ZIP deflate stream is truncated or malformed.")
                }
            }
            guard stream.avail_in == 0 else {
                throw ZipContainerError(code: "invalidZIP", summary: "ZIP member has unused compressed bytes.")
            }
        }
        return output
    }

    private static func validatePath(_ path: String) throws -> String {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        let reserved = Set(["CON", "PRN", "AUX", "NUL"] + (1...9).flatMap { ["COM\($0)", "LPT\($0)"] })
        let substantive = path.hasSuffix("/") ? components.dropLast() : components[...]
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0"),
              !path.hasPrefix("~"), !components.contains(where: { $0 == ".." || $0 == "." }),
              !components.first!.contains(":"),
              substantive.allSatisfy({ component in
                  !component.isEmpty && !component.contains(":") &&
                  !component.hasSuffix(" ") && !component.hasSuffix(".") &&
                  !reserved.contains(component.split(separator: ".", maxSplits: 1).first!.uppercased())
              }) else {
            throw ZipContainerError(code: "archivePathDenied", summary: "Archive member path is absolute or traverses outside the collection.")
        }
        return path
    }

    private static func u16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(u16(data, offset)) | UInt32(u16(data, offset + 2)) << 16
    }
}
