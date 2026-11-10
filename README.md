# Logic Pro Manager — Project Library + Audio Previews

macOS 14+ SwiftUI Xcode project. Open `LogicManager.xcodeproj` and select **My Mac**. Build with Cmd+B, run with Cmd+R.

## Features
- Scan `.logicx` projects, including package directories
- Search names, paths, genres, categories, instrumentation, producer/composer, statuses, keywords, notes, color tags, and collections
- Sort by modified, created, title, size, or genre; filter date ranges
- Custom color tags and virtual collections
- Browse only projects under a chosen indexed root folder
- Rename, move, duplicate, reveal, or open Logic projects (rename/move confirmation and collision checks)
- Detect audio previews in the same directory or `Audio`, `Exports`, `Bounces` subdirectories using project-name matching
- Manually link WAV, AIFF, MP3, M4A, or CAF; play/pause/seek inside inspector
- Separate persistent UserDefaults keys from Score Library Manager
- One-time import of legacy `LogicSessionManager.tags` and `LogicSessionManager.bookmarks` from the **same app preferences domain** only. If using a new bundle identifier, import will not automatically see the old app's data. Re-add folders as needed.

## Limitations
- This is a standalone source project, not an in-place patch of an existing Xcode target. Backup your old LogicManager project first.
- Audio is read from an exported bounce; Logic `.logicx` sessions are not rendered directly.
- Does not edit tracks, plugins, or MIDI inside `.logicx` files.
- Filesystem permissions and sandbox bookmarks may require reselecting folders.
- Not compiled on macOS in this environment; test with copies of projects before moving/renaming.

## Source and distribution

This repository contains the SwiftUI source and Xcode project. The uploaded archive does not contain a signed or notarized macOS app. Build locally in Xcode.

## License

No open-source license has been selected yet. All rights reserved unless a license is added by the project owner.
