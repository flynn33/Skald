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
