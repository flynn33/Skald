import SwiftUI

#if canImport(ForsettiCore) && canImport(ForsettiHostTemplate) && canImport(ForsettiPlatform)
import ForsettiCore
import ForsettiHostTemplate
import ForsettiPlatform
#endif

struct ContentView: View {
    @StateObject private var bootstrap = SkaldForsettiBootstrap()

    var body: some View {
        #if canImport(ForsettiCore) && canImport(ForsettiHostTemplate) && canImport(ForsettiPlatform)
        Group {
            switch SkaldDeploymentMode.current {
            case .development:
                ForsettiHostRootView(
                    controller: bootstrap.controller,
                    injectionRegistry: bootstrap.injectionRegistry,
                    showDeveloperControls: true,
                    launchActivationStrategy: .activateAllEligibleForDevelopment
                )
            case .production:
                SkaldProductionRootView(bootstrap: bootstrap)
            }
        }
        #else
        MissingForsettiProductsView()
        #endif
    }
}

#if canImport(ForsettiCore) && canImport(ForsettiHostTemplate) && canImport(ForsettiPlatform)
private struct SkaldProductionRootView: View {
    @ObservedObject var bootstrap: SkaldForsettiBootstrap

    var body: some View {
        Group {
            switch bootstrap.productionState {
            case .idle, .booting:
                ProgressView()
                    .frame(minWidth: 560, minHeight: 360)
            case .ready:
                SkaldAppModuleView()
            case .failed:
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundStyle(.orange)
                    Text("Unable to start Skald")
                        .font(.headline)
                    Text("Forsetti could not activate the Skald app module.")
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(minWidth: 560, minHeight: 360)
            }
        }
        .task {
            await bootstrap.bootForProduction()
        }
    }
}
#endif

private struct MissingForsettiProductsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            Text("Forsetti package products are missing")
                .font(.title2.bold())

            Text("Required products: ForsettiCore, ForsettiPlatform, ForsettiHostTemplate")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 360)
    }
}
