import AppKit
import Foundation

@MainActor
protocol FolderSelecting {
    func selectFolder() -> URL?
    func selectSources() -> [URL]
}

extension FolderSelecting {
    func selectSources() -> [URL] {
        selectFolder().map { [$0] } ?? []
    }
}

@MainActor
final class FolderSelectionService: FolderSelecting {
    func selectSources() -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = true
        return panel.runModal() == .OK ? panel.urls : []
    }

    func selectFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}
