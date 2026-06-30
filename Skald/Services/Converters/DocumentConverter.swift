import Foundation

nonisolated protocol DocumentConverter {
    var supportedExtensions: [String] { get }
    func convert(at url: URL, to format: OutputFormat) throws -> String
}
