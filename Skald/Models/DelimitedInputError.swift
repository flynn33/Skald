import Foundation

nonisolated struct DelimitedInputError: Error, Sendable {
    let code: String
    let stage: String
    let record: Int?
    let field: Int?
    let line: Int?
    let scalarOffset: Int?
    let summary: String

    init(code: String, stage: String, record: Int? = nil, field: Int? = nil, line: Int? = nil, scalarOffset: Int? = nil, summary: String) {
        self.code = code
        self.stage = stage
        self.record = record
        self.field = field
        self.line = line
        self.scalarOffset = scalarOffset
        self.summary = summary
    }
}

extension DelimitedInputError: LocalizedError {
    var errorDescription: String? {
        let location = [record.map { "record \($0)" }, field.map { "field \($0)" }, line.map { "line \($0)" }].compactMap { $0 }.joined(separator: ", ")
        return "\(code) during \(stage)\(location.isEmpty ? "" : " at \(location)"): \(summary)"
    }
}
