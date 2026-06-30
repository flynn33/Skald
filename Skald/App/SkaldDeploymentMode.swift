import Foundation

enum SkaldDeploymentMode: String {
    case development
    case production

    static let current: SkaldDeploymentMode = .production
}
