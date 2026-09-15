import Darwin
import Foundation

nonisolated enum OutputPublicationError: Error {
    case invalidTarget
    case invalidCandidate
    case targetChanged
    case exclusiveRenameUnsupported
    case collisionLimit
    case cancelled
    case io(stage: String, code: Int32)
}

extension OutputPublicationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidTarget: return "The selected target is not an accessible directory."
        case .invalidCandidate: return "The planned output is outside the selected target directory."
        case .targetChanged: return "The selected target directory changed during publication."
        case .exclusiveRenameUnsupported: return "This volume does not support exclusive output publication."
        case .collisionLimit: return "Too many output filename collisions."
        case .cancelled: return "Output publication was cancelled before commit."
        case let .io(stage, code): return "Output publication failed during \(stage): \(String(cString: strerror(code)))."
        }
    }
}
