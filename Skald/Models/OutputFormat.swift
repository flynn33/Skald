nonisolated enum OutputFormat: CaseIterable, Hashable, Identifiable, Sendable {
    case markdown
    case json

    var id: Self {
        self
    }

    var label: String {
        switch self {
        case .markdown:
            return "Markdown"
        case .json:
            return "JSON"
        }
    }
}

nonisolated enum OutputMode: CaseIterable, Hashable, Identifiable, Sendable {
    case markdown
    case json
    case both

    var id: Self { self }

    var label: String {
        switch self {
        case .markdown: return "Markdown"
        case .json: return "JSON"
        case .both: return "Both"
        }
    }

    var formats: [OutputFormat] {
        switch self {
        case .markdown: return [.markdown]
        case .json: return [.json]
        case .both: return [.markdown, .json]
        }
    }

    init(_ format: OutputFormat) {
        switch format {
        case .markdown: self = .markdown
        case .json: self = .json
        }
    }
}

extension OutputFormat {
    nonisolated var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .json: return "json"
        }
    }
}
