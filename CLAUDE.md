# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

(c)Copyright 2026 by Gennaro Eduardo Tangari.

## Language and file conventions

- Converse with the user in Italian. All documentation, code comments, identifiers, commit messages and UI strings' source text are written in American English.
- Every file you create must carry the copyright line `(c)Copyright 2026 by Gennaro Eduardo Tangari.` (documentation files: include it in the file; source files: via the header below).
- Every Swift source file starts with this header (fill in the file name, creation date and last update date; update "Last update" whenever the file is modified):

```swift
//
//  NOME_FILE.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on DATA_DI_CREAZIONE_DEL_FILE.
//  Last update: DATA_ULTIMO_UPDATE
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//
```

## What GTSync is

A native macOS app that keeps one or more directories in sync. Directories may be on the same disk or on different disks (including more than two disks). The product name shown to users is "GT Sync".

## Stack

- macOS only, SwiftUI, latest Swift (Xcode 27.x / Swift 6.x). Use Swift concurrency; no UIKit/iOS code.
- Must open in Xcode as a ready-to-use project/solution.
- UI must follow Apple's HIG for macOS and fully adopt Liquid Glass (use the `liquid-glass` and `swiftui-macos` skills when writing or reviewing views). The look should be attractive but always clear.

## Sync semantics (non-negotiable)

- **Always MERGE, never overwrite.** Every file and subfolder in every synced directory is preserved. A sync never replaces or deletes anything.
- **Name collision with different content:** the incoming file is still added, with a progressive suffix `-x` (x = integer, e.g. `report-1.pdf`, `report-2.pdf`). Compare the source hash against the destination file with the same name AND against all of its already-suffixed variants; add the file only if its hash differs from all of them. An identical hash means no copy.
- **Circular (bidirectional):** at the end of a sync, all participating directories must be identical and fully merged.

## Duplicates area

- A dedicated view lists every file and every possible duplicate, in two sections: same content (identical hash) and same name with different content (a name plus its `-x` variants; these are *different* files, and the user decides what to do: usually rename, or keep, or remove).
- The "main" file of a group is always the one with the **largest size on disk** (allocated size). All other members are duplicates; what happens to them is always the user's decision.
- The app may *recommend* removing or renaming; once the user confirms, it is applied in every folder that holds the file (removals go to the Trash). Never automatic.
- Selecting any file (source or destination) must show a preview so the user can judge easily.

## Commands

- Core engine tests: `swift test --package-path GTSyncCore`
- Build the app: `xcodebuild -project GTSync.xcodeproj -scheme GTSync -destination 'platform=macOS' build`
- App tests: `xcodebuild test -project GTSync.xcodeproj -scheme GTSync -destination 'platform=macOS'`
- The Xcode project was bootstrapped once with XcodeGen and is now maintained by hand/Xcode; there is no generator spec in the repo. Hardened Runtime only takes effect with real (non ad-hoc) signing.
