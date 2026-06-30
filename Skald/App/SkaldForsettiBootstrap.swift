import Combine
import Foundation
import SwiftUI

#if canImport(ForsettiCore) && canImport(ForsettiHostTemplate) && canImport(ForsettiPlatform)
import ForsettiCore
import ForsettiHostTemplate
import ForsettiPlatform

enum SkaldProductionBootState: Equatable {
    case idle
    case booting
    case ready
    case failed(String)
}

@MainActor
final class SkaldForsettiBootstrap: ObservableObject {
    let controller: ForsettiHostController
    let injectionRegistry: ForsettiViewInjectionRegistry
    @Published private(set) var productionState: SkaldProductionBootState = .idle

    init() {
        let registry = ModuleRegistry()
        do {
            try SkaldModuleRegistry.registerAll(into: registry)
        } catch {
            assertionFailure("Failed to register Skald module: \(error.localizedDescription)")
        }

        controller = ForsettiHostTemplateBootstrap.makeController(
            manifestsBundle: .main,
            moduleRegistry: registry,
            entitlementProvider: ForsettiEntitlementProviderFactory.makeDefault(),
            manifestsSubdirectory: "ForsettiManifests"
        )

        injectionRegistry = ForsettiViewInjectionRegistry()
        injectionRegistry.register(viewID: SkaldAppModule.Constants.primaryViewID) {
            SkaldAppModuleView()
        }
    }

    func bootForProduction() async {
        guard productionState != .ready, productionState != .booting else {
            return
        }

        productionState = .booting
        await controller.bootIfNeeded(
            activationStrategy: .activate(moduleIDs: Set([SkaldAppModule.Constants.moduleID]))
        )

        if controller.activeUIModuleID == SkaldAppModule.Constants.moduleID {
            productionState = .ready
            return
        }

        productionState = .failed(controller.errorMessage ?? "Activation failed.")
    }
}
#else
@MainActor
final class SkaldForsettiBootstrap: ObservableObject {
    enum ProductionBootState {
        case idle
    }

    let productionState = ProductionBootState.idle

    func bootForProduction() async {}
}
#endif
