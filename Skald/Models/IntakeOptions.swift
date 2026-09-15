import Foundation

nonisolated struct IntakeOptions: Sendable {
    let recursive: Bool
    let includeHidden: Bool
    let maximumItems: Int
    let maximumDepth: Int

    init(recursive: Bool = false, includeHidden: Bool = false, maximumItems: Int = 10_000, maximumDepth: Int = 32) {
        self.recursive = recursive
        self.includeHidden = includeHidden
        self.maximumItems = maximumItems
        self.maximumDepth = maximumDepth
    }
}

nonisolated enum IntakeError: Error, LocalizedError {
    case noSources
    case worklistLimit
    case depthLimit
    case alreadyRunning

    var errorDescription: String? {
        switch self {
        case .noSources: return "Select at least one source file or folder."
        case .worklistLimit: return "Input worklist exceeds its configured item limit."
        case .depthLimit: return "Input traversal exceeds its configured depth limit."
        case .alreadyRunning: return "A conversion is already running."
        }
    }
}
