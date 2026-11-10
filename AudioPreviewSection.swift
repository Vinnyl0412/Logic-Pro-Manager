import SwiftUI

struct AudioPreviewSection: View {
    let file: ScoreFile
    @ObservedObject private var manager = AudioPreviewManager.shared
    @StateObject private var player = AudioPreviewPlayer()
    @State private var previewURL: URL?
    @State private var isManual = false

    var body: some View {
        Section("Audio preview") {
            if let url = previewURL {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "waveform")
                        Text(url.lastPathComponent).lineLimit(1)
                        Spacer()
                        Text(isManual ? "Linked" : "Auto-detected")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button {
                            player.toggle()
                        } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        }
                        .disabled(player.duration <= 0)
                        Slider(value: Binding(
                            get: { player.position },
                            set: { player.seek($0) }
                        ), in: 0...max(player.duration, 0.01))
                        .disabled(player.duration <= 0)
                        Text(time(player.position) + " / " + time(player.duration))
                            .font(.caption.monospacedDigit()).frame(minWidth: 90)
                    }
                    if let error = player.error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
            } else {
                Text(manager.hasManualLink(file)
                     ? "Linked audio was not found. Choose a replacement or remove the link."
                     : "No matching bounce found. Link a WAV, AIFF, MP3, M4A or CAF file.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Link Audio…") { player.stop(); manager.chooseAudio(for: file); reload() }
                if manager.hasManualLink(file) {
                    Button("Remove Link") { player.stop(); manager.unlink(for: file); reload() }
                }
                Button("Rescan") { player.stop(); reload() }
                if let url = previewURL {
                    Button("Reveal Audio") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
            }
        }
        .onAppear { reload() }
        .onDisappear { player.stop() }
    }

    private func reload() {
        let result = manager.resolve(for: file)
        previewURL = result?.url
        isManual = result?.manuallyLinked ?? false
        if let url = previewURL { player.load(url) }
        else { player.stop() }
    }

    private func time(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(max(seconds, 0))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
