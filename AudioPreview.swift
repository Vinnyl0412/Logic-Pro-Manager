import Foundation
import AppKit
import AVFoundation
import UniformTypeIdentifiers
import Combine

// Links are stored separately from Logic projects. No audio is written into a project.
@MainActor
final class AudioPreviewManager: ObservableObject {
    static let shared = AudioPreviewManager()

    @Published private(set) var linkedFiles: [String: Data] = [:]
    private let key = "LogicManager.audioPreviewBookmarks.v1"
    private var accessURL: URL?

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: Data].self, from: data) {
            linkedFiles = decoded
        }
    }

    func chooseAudio(for score: ScoreFile) {
        let panel = NSOpenPanel()
        panel.title = "Choose Audio Preview for \(score.title)"
        panel.allowedContentTypes = [.audio]
        panel.allowsOtherFileTypes = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope],
                                                includingResourceValuesForKeys: nil,
                                                relativeTo: nil)
            linkedFiles[score.id] = bookmark
            persist()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func unlink(for score: ScoreFile) {
        linkedFiles.removeValue(forKey: score.id)
        persist()
    }

    func migrate(from oldURL: URL, to newURL: URL) {
        let old = oldURL.standardizedFileURL.path
        let new = newURL.standardizedFileURL.path
        if let bookmark = linkedFiles.removeValue(forKey: old) {
            linkedFiles[new] = bookmark
            persist()
        }
    }

    func duplicate(from score: ScoreFile, to newURL: URL) {
        if let bookmark = linkedFiles[score.id] {
            linkedFiles[newURL.standardizedFileURL.path] = bookmark
            persist()
        }
    }

    func resolve(for score: ScoreFile) -> (url: URL, manuallyLinked: Bool)? {
        if let bookmark = linkedFiles[score.id] {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark,
                                  options: [.withSecurityScope],
                                  relativeTo: nil, bookmarkDataIsStale: &stale),
               FileManager.default.fileExists(atPath: url.path) {
                if stale, let updated = try? url.bookmarkData(options: [.withSecurityScope],
                                         includingResourceValuesForKeys: nil, relativeTo: nil) {
                    linkedFiles[score.id] = updated
                    persist()
                }
                return (url, true)
            }
            // Preserve broken links so users can relink or explicitly remove them.
            return nil
        }
        return Self.findAutomaticPreview(for: score).map { ($0, false) }
    }

    func hasManualLink(_ score: ScoreFile) -> Bool { linkedFiles[score.id] != nil }

    // Keep access active while the audio player is using a sandboxed external file.
    func startAccess(_ url: URL) {
        stopAccess()
        if url.startAccessingSecurityScopedResource() { accessURL = url }
    }

    func stopAccess() {
        accessURL?.stopAccessingSecurityScopedResource()
        accessURL = nil
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(linkedFiles) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    nonisolated private static func findAutomaticPreview(for score: ScoreFile) -> URL? {
        let fm = FileManager.default
        let parent = score.url.deletingLastPathComponent()
        let folders = [parent, parent.appendingPathComponent("Audio"),
                       parent.appendingPathComponent("Exports"),
                       parent.appendingPathComponent("Bounces")]
        let allowed = Set(["wav", "aif", "aiff", "mp3", "m4a", "caf"])
        let preferred = ["wav", "aif", "aiff", "m4a", "mp3", "caf"]
        let stem = score.title.lowercased()
        var candidates: [URL] = []
        for folder in folders {
            guard let items = try? fm.contentsOfDirectory(at: folder,
                              includingPropertiesForKeys: [.isRegularFileKey],
                              options: [.skipsHiddenFiles]) else { continue }
            for url in items where allowed.contains(url.pathExtension.lowercased()) {
                let name = url.deletingPathExtension().lastPathComponent.lowercased()
                let match = name == stem || [" - ", "_", "-", " "].contains(where: { name.hasPrefix(stem + $0) })
                if match { candidates.append(url) }
            }
        }
        return candidates.sorted {
            let a = $0.deletingPathExtension().lastPathComponent.lowercased() == stem ? 0 : 1
            let b = $1.deletingPathExtension().lastPathComponent.lowercased() == stem ? 0 : 1
            if a != b { return a < b }
            let ai = preferred.firstIndex(of: $0.pathExtension.lowercased()) ?? 99
            let bi = preferred.firstIndex(of: $1.pathExtension.lowercased()) ?? 99
            if ai != bi { return ai < bi }
            return $0.path < $1.path
        }.first
    }
}

@MainActor
final class AudioPreviewPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var duration: TimeInterval = 0
    @Published var position: TimeInterval = 0
    @Published private(set) var error: String?
    private var player: AVAudioPlayer?
    private var timer: Timer?

    func load(_ url: URL) {
        stop()
        AudioPreviewManager.shared.startAccess(url)
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.prepareToPlay()
            player = newPlayer
            duration = newPlayer.duration
            error = nil
        } catch {
            self.error = "Cannot play this audio: \(error.localizedDescription)"
            AudioPreviewManager.shared.stopAccess()
        }
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            timer?.invalidate()
        } else {
            if player.currentTime >= player.duration { player.currentTime = 0 }
            isPlaying = player.play()
            timer?.invalidate()
            if isPlaying {
                timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.updatePosition() }
                }
            }
        }
    }

    func seek(_ value: TimeInterval) {
        player?.currentTime = min(max(value, 0), duration)
        position = player?.currentTime ?? 0
    }

    private func updatePosition() {
        guard let player else { return }
        position = player.currentTime
        if !player.isPlaying {
            isPlaying = false
            timer?.invalidate()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player?.stop()
        player = nil
        isPlaying = false
        position = 0
        duration = 0
        error = nil
        AudioPreviewManager.shared.stopAccess()
    }

    deinit { timer?.invalidate() }
}
