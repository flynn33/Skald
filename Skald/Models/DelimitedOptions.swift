import Foundation

nonisolated enum TextEncodingChoice: String, CaseIterable, Hashable, Identifiable, Sendable {
    case automatic, utf8, utf16LittleEndian, utf16BigEndian, utf32LittleEndian, utf32BigEndian, windows1252, latin1
    var id: Self { self }
    var label: String {
        switch self {
        case .automatic: return "Automatic (BOM / UTF-8)"
        case .utf8: return "UTF-8"
        case .utf16LittleEndian: return "UTF-16 LE"
        case .utf16BigEndian: return "UTF-16 BE"
        case .utf32LittleEndian: return "UTF-32 LE"
        case .utf32BigEndian: return "UTF-32 BE"
        case .windows1252: return "Windows-1252"
        case .latin1: return "Latin-1"
        }
    }
}

nonisolated enum DelimiterChoice: Hashable, Sendable {
    case automatic, comma, tab, semicolon, custom(String)
    static let pickerChoices: [Self] = [.automatic, .comma, .tab, .semicolon]
    var label: String {
        switch self {
        case .automatic: return "Automatic"
        case .comma: return "Comma"
        case .tab: return "Tab"
        case .semicolon: return "Semicolon"
        case .custom(let value): return "Custom: \(value)"
        }
    }
}

nonisolated enum HeaderMode: String, CaseIterable, Hashable, Identifiable, Sendable {
    case automatic, present, absent
    var id: Self { self }
    var label: String {
        switch self {
        case .automatic: return "Automatic (keep first record)"
        case .present: return "First record is header"
        case .absent: return "No header"
        }
    }
}

nonisolated struct DelimitedOptions: Sendable {
    let encoding: TextEncodingChoice
    let delimiter: DelimiterChoice
    let header: HeaderMode
    let allowSepPreamble: Bool
    init(encoding: TextEncodingChoice = .automatic, delimiter: DelimiterChoice = .automatic, header: HeaderMode = .automatic, allowSepPreamble: Bool = false) {
        self.encoding = encoding
        self.delimiter = delimiter
        self.header = header
        self.allowSepPreamble = allowSepPreamble
    }
}

nonisolated struct AppliedDelimitedSettings: Codable, Sendable {
    let encoding: String
    let encodingProvenance: String
    let delimiter: String
    let headerMode: String
    let headerConfirmed: Bool
    let diagnostics: [String]
}

nonisolated struct DelimitedDiagnostic: Sendable {
    let code: String
}

nonisolated struct InterpretedDelimitedText: Sendable {
    let originalHeader: [String]?
    let dataRows: [[String]]
    let diagnostics: [DelimitedDiagnostic]
    let headerConfirmed: Bool
}

nonisolated struct DecodedText: Sendable {
    let text: String
    let encoding: String
    let provenance: String
}
