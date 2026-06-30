import Foundation

nonisolated struct ReadableDocument: Codable {
    let version: String
    let source: ReadableSource
    let summary: ReadableSummary
    let content: ReadableContent
}

nonisolated struct ReadableSource: Codable {
    let fileName: String
    let fileExtension: String
    let convertedAt: String
}

nonisolated struct ReadableSummary: Codable {
    let blockCount: Int
    let pageCount: Int?
    let tableCount: Int?
    let dataPresent: Bool?
}

nonisolated struct ReadableContent: Codable {
    let blocks: [ReadableBlock]?
    let pages: [ReadablePage]?
    let tables: [ReadableTable]?
    let data: ReadableValue?
}

nonisolated struct ReadablePage: Codable {
    let page: Int
    let blockCount: Int
    let blocks: [ReadableBlock]
}

nonisolated enum ReadableBlockType: String, Codable {
    case heading
    case paragraph
    case listItem
    case code
}

nonisolated enum ReadableListStyle: String, Codable {
    case unordered
    case ordered
}

nonisolated struct ReadableBlock: Codable {
    let order: Int
    let type: ReadableBlockType
    let text: String
    let headingLevel: Int?
    let listStyle: ReadableListStyle?
    let listDepth: Int?
    let listIndex: Int?
}

nonisolated struct ReadableTable: Codable {
    let title: String?
    let columns: [String]
    let rows: [[String]]
}

nonisolated indirect enum ReadableValue: Codable {
    case object([String: ReadableValue])
    case array([ReadableValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
            return
        }

        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }

        if let value = try? container.decode(Double.self) {
            self = .number(value)
            return
        }

        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }

        if let value = try? container.decode([ReadableValue].self) {
            self = .array(value)
            return
        }

        if let value = try? container.decode([String: ReadableValue].self) {
            self = .object(value)
            return
        }

        throw DecodingError.typeMismatch(
            ReadableValue.self,
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported ReadableValue")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}
