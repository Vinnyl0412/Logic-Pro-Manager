import Foundation
import AppKit
import Combine

@MainActor final class ScoreStore: ObservableObject {
    @Published private(set) var files: [ScoreFile] = []
    @Published private(set) var folders: [URL] = []
    @Published var metadata: [String: ScoreMetadata] = [:] { didSet { persistMetadata() } }
    @Published var colorTags: [ColorTag] = [] { didSet { saveOrganization() } }
    @Published var collections: [ScoreCollection] = [] { didSet { saveOrganization() } }
    @Published var scanning = false
    @Published var errorMessage: String?

    private var accessURLs: [URL] = []
    private var scanTask: Task<Void, Never>?
    private let bookmarksKey = "LogicManager.folderBookmarks.v1"
    private let metadataKey = "LogicManager.scoreMetadata.v1"
    private let organizationKey = "LogicManager.organization.v1"

    private struct Organization: Codable {
        var tags: [ColorTag]
        var collections: [ScoreCollection]
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: metadataKey),
           let value = try? JSONDecoder().decode([String: ScoreMetadata].self, from: data) {
            metadata = value
        }
        if let data = UserDefaults.standard.data(forKey: organizationKey),
           let organization = try? JSONDecoder().decode(Organization.self, from: data) {
            colorTags = organization.tags
            collections = organization.collections
        }
        // One-time import of the original Logic Session Manager folder bookmarks and tags.
        if UserDefaults.standard.data(forKey: metadataKey) == nil,
           let legacy = UserDefaults.standard.data(forKey: "LogicSessionManager.tags"),
           let oldTags = try? JSONDecoder().decode([String: LegacyLogicTags].self, from: legacy) {
            metadata = oldTags.mapValues { old in
                var value = ScoreMetadata()
                value.genre = old.genre
                value.status = old.status
                value.favorite = old.favorite
                return value
            }
        }
        let saved = (UserDefaults.standard.array(forKey: bookmarksKey) as? [Data])
            ?? (UserDefaults.standard.array(forKey: "LogicSessionManager.bookmarks") as? [Data])
            ?? []
        for bookmark in saved {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) {
                if url.startAccessingSecurityScopedResource() { accessURLs.append(url) }
                if !folders.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) { folders.append(url) }
            }
        }
        refresh()
    }

    func addFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add Logic Project Folder"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !folders.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) {
            if url.startAccessingSecurityScopedResource() { accessURLs.append(url) }
            folders.append(url)
        }
        persistBookmarks()
        refresh()
    }

    func removeFolder(_ url: URL) {
        folders.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        accessURLs.removeAll { active in
            if active.standardizedFileURL == url.standardizedFileURL {
                active.stopAccessingSecurityScopedResource()
                return true
            }
            return false
        }
        persistBookmarks()
        refresh()
    }

    private func persistBookmarks() {
        let data = folders.compactMap { try? $0.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) }
        UserDefaults.standard.set(data, forKey: bookmarksKey)
    }

    private func persistMetadata() {
        if let data = try? JSONEncoder().encode(metadata) { UserDefaults.standard.set(data, forKey: metadataKey) }
    }

    private func saveOrganization() {
        let value = Organization(tags: colorTags, collections: collections)
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: organizationKey)
        }
    }

    func createTag(name: String, hex: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        colorTags.append(ColorTag(name: cleaned, hex: hex))
    }

    func renameTag(_ id: UUID, name: String, hex: String) {
        guard let index = colorTags.firstIndex(where: { $0.id == id }) else { return }
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        colorTags[index].name = cleaned
        colorTags[index].hex = hex
    }

    func deleteTag(_ id: UUID) {
        colorTags.removeAll { $0.id == id }
        for (key, var value) in metadata where value.colorTagIDs.contains(id) {
            value.colorTagIDs.removeAll { $0 == id }
            metadata[key] = value
        }
    }

    func createCollection(name: String, hex: String = "#8B5CF6") {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        collections.append(ScoreCollection(name: cleaned, hex: hex))
    }

    func renameCollection(_ id: UUID, name: String, hex: String? = nil) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let index = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[index].name = cleaned
        if let hex { collections[index].hex = hex }
    }

    func deleteCollection(_ id: UUID) {
        collections.removeAll { $0.id == id }
        for (key, var value) in metadata where value.collectionIDs.contains(id) {
            value.collectionIDs.removeAll { $0 == id }
            metadata[key] = value
        }
    }

    func toggleTag(_ id: UUID, on file: ScoreFile) {
        var value = info(file)
        if value.colorTagIDs.contains(id) { value.colorTagIDs.removeAll { $0 == id } }
        else { value.colorTagIDs.append(id) }
        update(file, value)
    }

    func toggleCollection(_ id: UUID, on file: ScoreFile) {
        var value = info(file)
        if value.collectionIDs.contains(id) { value.collectionIDs.removeAll { $0 == id } }
        else { value.collectionIDs.append(id) }
        update(file, value)
    }

    func info(_ file: ScoreFile) -> ScoreMetadata { metadata[file.id] ?? ScoreMetadata() }
    func update(_ file: ScoreFile, _ value: ScoreMetadata) { metadata[file.id] = value }
    func open(_ file: ScoreFile) { NSWorkspace.shared.open(file.url) }
    func reveal(_ file: ScoreFile) { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }

    func duplicate(_ file: ScoreFile) {
        let folder = file.url.deletingLastPathComponent()
        let stem = file.title
        var index = 1
        var target: URL
        repeat {
            target = folder.appendingPathComponent("\(stem) Copy \(index)").appendingPathExtension(file.fileExtension)
            index += 1
        } while FileManager.default.fileExists(atPath: target.path)
        do {
            try FileManager.default.copyItem(at: file.url, to: target)
            metadata[target.standardizedFileURL.path] = info(file)
            AudioPreviewManager.shared.duplicate(from: file, to: target)
            refresh()
        } catch {
            errorMessage = "Could not duplicate project: \(error.localizedDescription)"
        }
    }

    // Filesystem operations require confirmation. We never overwrite an existing file.
    private func confirmFileChange(_ message: String, detail: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func migrateMetadata(from oldURL: URL, to newURL: URL) {
        let oldKey = oldURL.standardizedFileURL.path
        let newKey = newURL.standardizedFileURL.path
        AudioPreviewManager.shared.migrate(from: oldURL, to: newURL)
        if let previous = metadata.removeValue(forKey: oldKey) {
            metadata[newKey] = previous
        }
    }

    func rename(_ file: ScoreFile, to newName: String) {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains(":") else {
            errorMessage = "Enter a valid file name without slashes or colons."
            return
        }
        guard name != file.title else { return }
        let destination = file.url.deletingLastPathComponent()
            .appendingPathComponent(name).appendingPathExtension(file.fileExtension)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            errorMessage = "A file with that name already exists."
            return
        }
        guard confirmFileChange("Rename project?", detail: "\(file.url.lastPathComponent) → \(destination.lastPathComponent)\nThe original file will be renamed on disk.") else { return }
        do {
            try FileManager.default.moveItem(at: file.url, to: destination)
            migrateMetadata(from: file.url, to: destination)
            refresh()
        } catch { errorMessage = "Rename failed: \(error.localizedDescription)" }
    }

    func moveToFolder(_ file: ScoreFile) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose Destination"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let destination = folder.appendingPathComponent(file.url.lastPathComponent)
        guard destination.standardizedFileURL != file.url.standardizedFileURL else { return }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            errorMessage = "A file with this name already exists in the destination."
            return
        }
        guard confirmFileChange("Move project?", detail: "From: \(file.url.deletingLastPathComponent().path)\nTo: \(folder.path)\nThis changes the file's physical location.") else { return }
        do {
            try FileManager.default.moveItem(at: file.url, to: destination)
            migrateMetadata(from: file.url, to: destination)
            // Add the destination to the indexed folders if it is outside existing roots.
            if !folders.contains(where: { destination.path.hasPrefix($0.standardizedFileURL.path + "/") }) {
                if folder.startAccessingSecurityScopedResource() { accessURLs.append(folder) }
                folders.append(folder)
                persistBookmarks()
            }
            refresh()
        } catch { errorMessage = "Move failed: \(error.localizedDescription)" }
    }

    func refresh() {
        scanTask?.cancel()
        let roots = folders
        scanning = true
        scanTask = Task {
            let results = await Task.detached(priority: .userInitiated) {
                Self.scan(roots)
            }.value
            guard !Task.isCancelled else { return }
            files = results.sorted { $0.modified > $1.modified }
            scanning = false
        }
    }

    nonisolated private static func diskUsage(_ url: URL, values: URLResourceValues?) -> Int64 {
        guard values?.isDirectory == true else {
            return Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey]
        guard let items = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let child as URL in items {
            if Task.isCancelled { break }
            if let info = try? child.resourceValues(forKeys: keys), info.isRegularFile == true {
                total += Int64(info.totalFileAllocatedSize ?? info.fileSize ?? 0)
            }
        }
        return total
    }

    nonisolated private static func scan(_ folders: [URL]) -> [ScoreFile] {
        var output: [ScoreFile] = []
        var seen = Set<String>()
        let keys: Set<URLResourceKey> = [.creationDateKey, .contentModificationDateKey, .fileSizeKey, .totalFileAllocatedSizeKey, .isDirectoryKey]
        for folder in folders {
            guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true }) else { continue }
            while let url = enumerator.nextObject() as? URL {
                if Task.isCancelled { return output }
                let ext = url.pathExtension.lowercased()
                guard let format = ScoreFormat.allCases.first(where: { $0.extensions.contains(ext) }) else { continue }
                enumerator.skipDescendants()
                let path = url.standardizedFileURL.path
                guard seen.insert(path).inserted else { continue }
                let values = try? url.resourceValues(forKeys: keys)
                let size = diskUsage(url, values: values)
                output.append(ScoreFile(url: url, format: format, created: values?.creationDate ?? .distantPast, modified: values?.contentModificationDate ?? .distantPast, bytes: size))
            }
        }
        return output
    }
}

private struct LegacyLogicTags: Codable {
    var genre: String
    var status: String
    var favorite: Bool
}
