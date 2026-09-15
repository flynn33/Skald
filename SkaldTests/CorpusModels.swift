import Foundation

/// Decode the independent oracle in the test target, never in the production app.
struct DelimitedCorpus: Decodable {
    let version: Int
    let cases: [DelimitedCase]
    let performanceCase: PerformanceCase
}

struct DelimitedCase: Decodable {
    let id: String
    let file: String
    let sha256: String
    let encoding: String
    let delimiter: String
    let headerMode: String
    let expectedParserRows: [[String]]?
    let expectedDataRows: [[String]]?
    let expectedOriginalHeader: [String]?
    let expectedError: String?
    let expectedDiagnostics: [String]
}

struct PerformanceCase: Decodable {
    let file: String
    let sha256: String
    let syntacticRecordCount: Int
    let dataRecordCount: Int
    let headerMode: String
    let maximumMarkdownBytesExclusive: Int
}
