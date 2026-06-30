import AppKit
import Foundation

@MainActor
protocol FolderSelecting {
    func selectFolder() -> URL?
}

@MainActor
final class FolderSelectionService: FolderSelecting {
    func selectFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}
