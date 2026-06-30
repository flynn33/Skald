#if canImport(ForsettiCore)
import ForsettiCore

enum SkaldModuleRegistry {
    static func registerAll(into registry: ModuleRegistry) throws {
        try registry.register(entryPoint: SkaldAppModule.Constants.entryPoint) {
            SkaldAppModule()
        }
    }
}
#else
enum SkaldModuleRegistry {}
#endif
