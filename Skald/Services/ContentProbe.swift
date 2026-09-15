import Darwin
import Foundation

nonisolated enum ContentProbeResult {
    case compatible
    case strictText
    case binary
    case extensionConflict(String)
}

nonisolated final class ContentProbe {
    private let sampleLimit: Int
    init(sampleLimit: Int = 8_192) { self.sampleLimit = max(1, sampleLimit) }

    func inspect(_ url: URL, fileExtension: String, knownExtension: Bool) throws -> ContentProbeResult {
        if fileExtension == "rtfd" { return .compatible }
        let descriptor = url.path.withCString { Darwin.open($0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK) }
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        var fileInfo = stat()
        guard fstat(descriptor, &fileInfo) == 0,
              (fileInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            _ = Darwin.close(descriptor)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EINVAL))
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: sampleLimit) ?? Data()
        let bytes = Array(data)
        let fullSize = try handle.seekToEnd()
        if ["csv", "tsv"].contains(fileExtension), knownExtension,
           bytes.starts(with: [0xEF, 0xBB, 0xBF]) || bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]) || bytes.starts(with: [0x00, 0x00, 0xFE, 0xFF]) {
            return .compatible
        }
        let signature: String? = {
            if bytes.starts(with: Array("%PDF-".utf8)) { return "pdf" }
            if bytes.starts(with: [0x50, 0x4B, 0x03, 0x04]) { return "zip" }
            if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
            if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
            if bytes.starts(with: [0x49, 0x49, 0x2A, 0x00]) || bytes.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) { return "tiff" }
            if bytes.starts(with: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) { return "ole" }
            if bytes.starts(with: Array("bplist00".utf8)) { return "bplist" }
            if bytes.count >= 12, Array(bytes[4..<8]) == Array("ftyp".utf8),
               ["heic", "heix", "hevc", "heif", "heim", "heis", "mif1"].contains(String(decoding: bytes[8..<12], as: UTF8.self)) { return "heic" }
            return nil
        }()
        if let signature {
            let allowed: Set<String> = {
                switch signature {
                case "pdf": return ["pdf"]
                case "zip": return ["zip", "docx", "odt", "xlsx", "ods"]
                case "png": return ["png"]
                case "jpg": return ["jpg", "jpeg"]
                case "tiff": return ["tif", "tiff"]
                case "ole": return ["doc", "xls"]
                case "bplist": return ["plist", "webarchive"]
                case "heic": return ["heic"]
                default: return []
                }
            }()
            return allowed.contains(fileExtension) ? .compatible : .extensionConflict(signature)
        }
        if fileExtension == "pdf" && !bytes.isEmpty { return .extensionConflict("plain/non-PDF") }
        if ["png", "jpg", "jpeg", "tif", "tiff", "heic"].contains(fileExtension) && !bytes.isEmpty { return .extensionConflict("non-image") }
        let textual = !bytes.contains(0) && !bytes.contains(where: { $0 < 0x20 && $0 != 0x09 && $0 != 0x0A && $0 != 0x0D })
        guard textual else { return knownExtension ? .extensionConflict("binary") : .binary }
        if ["csv", "tsv"].contains(fileExtension) && knownExtension { return .compatible }
        var sample = bytes
        var decoded: String?
        let boundaryTrims = fullSize > UInt64(sampleLimit) ? 3 : 0
        for _ in 0...boundaryTrims {
            decoded = String(data: Data(sample), encoding: .utf8)
            if decoded != nil { break }
            guard !sample.isEmpty else { break }
            sample.removeLast()
        }
        guard decoded != nil else { return knownExtension ? .extensionConflict("invalid UTF-8/binary") : .binary }
        return knownExtension ? .compatible : .strictText
    }
}
