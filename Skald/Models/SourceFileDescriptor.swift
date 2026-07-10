import Foundation

nonisolated struct SourceFileDescriptor: Sendable {
    let url: URL
    let baseName: String
    let reportBaseName: String
    let fileExtension: String
    let isHidden: Bool

    init(url: URL) {
        self.url = url

        let lastPathComponent = url.lastPathComponent
        let nativeExtension = url.pathExtension.lowercased()
        isHidden = lastPathComponent.hasPrefix(".")

        if nativeExtension.isEmpty,
           lastPathComponent.hasPrefix("."),
           lastPathComponent.count > 1,
           !lastPathComponent.dropFirst().contains(".") {
            let dotFileName = String(lastPathComponent.dropFirst())
            baseName = dotFileName
            reportBaseName = ""
            fileExtension = dotFileName.lowercased()
        } else {
            baseName = url.deletingPathExtension().lastPathComponent
            reportBaseName = baseName
            fileExtension = nativeExtension
        }
    }
}
