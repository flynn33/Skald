import Foundation

/// Reads one bounded snapshot; legacy encodings are accepted only when the
/// strict UTF-8/BOM paths do not decode the complete file.
nonisolated enum TextFileReader {
    static func read(_ url: URL, maximumInputBytes: Int = 16 * 1_024 * 1_024) throws -> String {
        let data = try BoundedInputReader.read(url, maximumBytes: maximumInputBytes)
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        if data.starts(with: [0x00, 0x00, 0xFE, 0xFF]) || data.starts(with: [0xFF, 0xFE, 0x00, 0x00]) {
            if let utf32 = String(data: data, encoding: .utf32) { return utf32 }
        }
        if data.starts(with: [0xFE, 0xFF]) || data.starts(with: [0xFF, 0xFE]) {
            if let utf16 = String(data: data, encoding: .utf16) { return utf16 }
        }
        if let windows1252 = String(data: data, encoding: .windowsCP1252) { return windows1252 }
        if let latin1 = String(data: data, encoding: .isoLatin1) { return latin1 }
        throw InputDiagnostic(code: "invalidTextEncoding", stage: "decode", fileName: url.lastPathComponent,
                              summary: "Text bytes cannot be decoded with a supported encoding.")
    }
}
