import Foundation

/// Robust text loading for converters that accept arbitrary text-based files.
/// Tries UTF-8, then the system's best-guess encoding, then Latin-1 so that
/// non-UTF-8 files still convert rather than failing outright.
nonisolated enum TextFileReader {
    static func read(_ url: URL) throws -> String {
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            return utf8
        }

        var detected: String.Encoding = .utf8
        if let smart = try? String(contentsOf: url, usedEncoding: &detected) {
            return smart
        }

        if let data = try? Data(contentsOf: url),
           let latin1 = String(data: data, encoding: .isoLatin1) {
            return latin1
        }

        throw ConversionError.invalidDocument
    }
}
