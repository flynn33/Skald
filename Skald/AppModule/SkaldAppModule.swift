#if canImport(ForsettiCore)
import Foundation
import ForsettiCore

final class SkaldAppModule: ForsettiAppModule {
    enum Constants {
        static let moduleID = "com.daley.jim.skald.app-module"
        static let entryPoint = "SkaldAppModule"
        static let primaryViewID = "com.daley.jim.skald.app-module.workspace"
    }

    let descriptor = ModuleDescriptor(
        moduleID: Constants.moduleID,
        displayName: "Skald",
        moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
        moduleType: .app
    )

    let manifest = ModuleManifest(
        schemaVersion: ModuleManifest.currentSchemaVersion,
        manifestTemplateVersion: .current,
        moduleID: Constants.moduleID,
        displayName: "Skald",
        moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
        moduleType: .app,
        supportedPlatforms: [.macOS],
        minForsettiVersion: SemVer(major: 0, minor: 1, patch: 0),
        capabilitiesRequested: [.storage, .fileExport, .viewInjection],
        iapProductID: nil,
        entryPoint: Constants.entryPoint,
        defaultModuleRole: .ui,
        runtimeRequirements: ModuleRuntimeRequirements(
            io: [
                ModuleIORequirement(
                    requirementID: "com.daley.jim.skald.read-source-folder",
                    kind: .storage,
                    access: .read,
                    required: true
                ),
                ModuleIORequirement(
                    requirementID: "com.daley.jim.skald.write-target-folder",
                    kind: .fileExport,
                    access: .write,
                    required: true
                )
            ],
            ui: ModuleUIRequirements(
                viewIDs: [Constants.primaryViewID],
                slotIDs: ["module.workspace"]
            )
        )
    )

    let uiContributions = UIContributions(
        viewInjections: [
            ViewInjectionDescriptor(
                injectionID: "com.daley.jim.skald.app-module.workspace",
                slot: "module.workspace",
                viewID: Constants.primaryViewID,
                priority: 100
            )
        ]
    )

    private var isStarted = false

    init() {}

    func start(context: any ForsettiModuleContext) throws {
        guard !isStarted else { return }

        isStarted = true
        context.logger.info("Skald app module started")
    }

    func stop(context: any ForsettiModuleContext) {
        guard isStarted else { return }

        isStarted = false
        context.logger.info("Skald app module stopped")
    }
}
#endif
