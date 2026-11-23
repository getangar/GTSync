# GT Sync

(c)Copyright 2026 by Gennaro Eduardo Tangari.

**GT Sync keeps two or more folders in sync on your Mac, without ever overwriting or silently deleting anything.**
The folders can live on the same disk or on different disks, including external ones. It is a native macOS app
built with SwiftUI and Liquid Glass.

## How it works

GT Sync always **merges**. Everything in every folder is preserved, and when the sync is done all folders are identical.

- **Nothing is overwritten.** If two files share a name but have different content, both are kept: the second one is added as `name-1.ext`, `name-2.ext`, and so on. A file is only added if its content differs from the same-named file and from all of its numbered variants (compared by SHA-256).
- **Circular sync.** Every folder receives what the others have, so they end up the same.
- **Intentional deletions are respected, safely.** If you delete a file in one folder, GT Sync does not copy it back and does not delete it elsewhere on its own. It shows up in **Review**, where you choose to restore it or move it to the Trash everywhere.
- **Renames are recognized.** A file that disappears and reappears under another name with the same content is a rename, not a deletion plus a new file.
- **Removals always go to the Trash**, and only after you confirm.
- **A missing disk is never read as a deletion.** If a folder is unmounted or unreadable, nothing runs. A folder that is suddenly empty stops the sync until you confirm it is a new disk.

## What you can do

- **Overview:** your folders as cards, with their state and free space. Syncing is manual and always starts with a **plan preview**: what will be added, renamed or kept, before anything happens.
- **Files:** every file across all folders, where it lives, and its status, with a preview in the inspector.
- **Duplicates:** two kinds, shown separately.
  - *Same content* under different names or folders.
  - *Same name, different content*: different files that collided on a name. You decide what to do (usually rename).
  
  The "main" file of a group is the one with the largest size on disk. All the others are yours to keep, rename or move to the Trash, in every folder at once, with previews side by side.
- **Review:** pending deletions waiting for your decision.
- **History:** what each sync did.
- **Settings:** extra file names to ignore (`.DS_Store`, `._*` and similar are always ignored).

The interface is in English and Italian.

## Requirements

- macOS 26 or later (Liquid Glass)
- Xcode 27 and Swift 6 to build

## Build and test

```sh
# Open in Xcode
open GTSync.xcodeproj

# Engine tests (GTSyncCore)
swift test --package-path GTSyncCore

# Build the app
xcodebuild -project GTSync.xcodeproj -scheme GTSync -destination 'platform=macOS' build

# App tests
xcodebuild test -project GTSync.xcodeproj -scheme GTSync -destination 'platform=macOS'
```

## Project layout

| Path | What it is |
|---|---|
| `GTSync/` | The SwiftUI app: models, views, settings, localization. |
| `GTSyncCore/` | A Swift package with the sync engine: scanner, hasher, planner, executor, duplicate index. Tested without any UI. |
| `GTSyncTests/` | App tests. |
| `docs/superpowers/` | Design documents (behavior and GUI) and the implementation plan. |

The app is sandboxed and uses the Hardened Runtime, and folders are accessed through security-scoped bookmarks, so it is ready for the Mac App Store when the time comes.

## Status

Version 1 is feature complete for manual sync. Not done yet: automatic (continuous) sync, Developer ID signing and notarization, and the final app icon.

## Contributing

Each new feature is developed on its own branch and merged into `main` through a pull request.

## Copyright

Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
