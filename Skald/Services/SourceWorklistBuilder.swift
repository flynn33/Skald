import Darwin
import Foundation

nonisolated struct SourceWorkItem {
    let url: URL
    let isConvertible: Bool
    let message: String?
}

nonisolated struct SourceWorklist {
    let items: [SourceWorkItem]
}

nonisolated final class SourceWorklistBuilder {
    private struct Identity: Hashable {
        let device: dev_t
        let inode: ino_t
    }

    func snapshot(selections: [URL], target: URL, options: IntakeOptions) throws -> SourceWorklist {
        guard !selections.isEmpty else { throw IntakeError.noSources }
        guard options.maximumItems > 0, options.maximumDepth >= 0 else { throw IntakeError.worklistLimit }
        let targetPath = target.standardizedFileURL.path
        var seen = Set<Identity>()
        var items: [SourceWorkItem] = []

        func append(_ url: URL, convertible: Bool, message: String? = nil) throws {
            guard items.count < options.maximumItems else { throw IntakeError.worklistLimit }
            items.append(SourceWorkItem(url: url, isConvertible: convertible, message: message))
        }

        func visit(_ url: URL, depth: Int, explicit: Bool) throws {
            guard depth <= options.maximumDepth else { throw IntakeError.depthLimit }
            var info = stat()
            guard lstat(url.path, &info) == 0 else {
                try append(url, convertible: false, message: "Cannot inspect input: \(String(cString: strerror(errno))).")
                return
            }
            let identity = Identity(device: info.st_dev, inode: info.st_ino)
            guard seen.insert(identity).inserted else {
                try append(url, convertible: false, message: "Duplicate input identity.")
                return
            }
            let kind = info.st_mode & mode_t(S_IFMT)
            if kind == mode_t(S_IFLNK) {
                try append(url, convertible: false, message: "Symbolic link is not followed; select its authorized target directly.")
                return
            }
            if kind == mode_t(S_IFDIR) {
                let ext = url.pathExtension.lowercased()
                if ext == "rtfd" {
                    try append(url, convertible: true)
                    return
                }
                if ["app", "bundle", "framework", "xcarchive"].contains(ext) {
                    try append(url, convertible: false, message: "Application/package directory is not a document collection.")
                    return
                }
                if !explicit && url.standardizedFileURL.path == targetPath {
                    return
                }
                if !explicit && !options.recursive {
                    try append(url, convertible: false, message: "Directory (recursive conversion off).")
                    return
                }
                let children: [URL]
                do {
                    children = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])
                } catch {
                    try append(url, convertible: false, message: "Cannot read directory: \(error.localizedDescription)")
                    return
                }
                for child in children.sorted(by: { left, right in
                    let a = left.lastPathComponent.lowercased()
                    let b = right.lastPathComponent.lowercased()
                    return a == b ? left.lastPathComponent < right.lastPathComponent : a < b
                }) {
                    if url.standardizedFileURL.path != targetPath && child.standardizedFileURL.path == targetPath { continue }
                    let descriptor = SourceFileDescriptor(url: child)
                    if descriptor.isHidden && !options.includeHidden && !isSupportedDotfile(descriptor) {
                        try append(child, convertible: false, message: "Hidden input (include hidden off).")
                        continue
                    }
                    try visit(child, depth: depth + 1, explicit: false)
                }
                return
            }
            if kind == mode_t(S_IFREG) {
                try append(url, convertible: true)
                return
            }
            try append(url, convertible: false, message: "Special file is not a regular document.")
        }

        for selection in selections {
            try visit(selection, depth: 0, explicit: true)
        }
        return SourceWorklist(items: items)
    }

    private func isSupportedDotfile(_ source: SourceFileDescriptor) -> Bool {
        source.isHidden && ["env", "ini", "cfg", "conf", "properties", "json", "csv", "tsv", "txt", "md"].contains(source.fileExtension)
    }

}
