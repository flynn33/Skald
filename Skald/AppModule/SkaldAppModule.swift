import Foundation

final class SkaldAppModule {
    enum Constants {
        static let moduleID = "com.daley.jim.skald.app-module"
        static let entryPoint = "SkaldAppModule"
        static let primaryViewID = "com.daley.jim.skald.app-module.workspace"
        static let manifestResourceName = "SkaldAppModuleManifest"
    }

    let descriptor = SkaldAppModuleDescriptor(
        moduleID: Constants.moduleID,
        displayName: "Skald",
        moduleVersion: "1.0.0",
        moduleType: .app,
        supportedPlatforms: [.macOS]
    )
}

struct SkaldAppModuleDescriptor: Equatable {
    let moduleID: String
    let displayName: String
    let moduleVersion: String
    let moduleType: SkaldModuleType
    let supportedPlatforms: [SkaldPlatform]
}

enum SkaldModuleType: String {
    case app
}

enum SkaldPlatform: String {
    case macOS
}
