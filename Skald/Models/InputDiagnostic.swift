import Foundation

nonisolated struct InputDiagnostic: Error, LocalizedError {
    let code: String
    let stage: String
    let fileName: String?
    let page: Int?
    let record: Int?
    let summary: String
    let underlying: Error?

    init(code: String, stage: String, fileName: String? = nil, page: Int? = nil, record: Int? = nil,
         summary: String, underlying: Error? = nil) {
        self.code = code
        self.stage = stage
        self.fileName = fileName
        self.page = page
        self.record = record
        self.summary = summary
        self.underlying = underlying
    }

    var errorDescription: String? {
        let location = page.map { " page \($0)" } ?? record.map { " record \($0)" } ?? ""
        return "\(code) (\(stage)\(location)): \(summary)"
    }
}
