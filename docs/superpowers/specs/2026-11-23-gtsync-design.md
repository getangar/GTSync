# GT Sync — Design

(c)Copyright 2026 by Gennaro Eduardo Tangari.

Date: 2026-11-23 · Status: **draft, awaiting approval**

## 1. Intent

GT Sync is a native macOS app that keeps two or more directories (same disk or different disks) circularly in sync using strict **merge** semantics: nothing is ever lost, overwritten, or silently deleted. It also gives the user a clear place to inspect every file and every duplicate, with previews, and to safely clean up.

Why: the author wants to consolidate and mirror data across disks without the data-loss risk of classic "mirror" sync tools.

## 2. Goals, non-goals, anti-goals

**Goals**
- Circular merge across N directories; at the end of a sync all participating directories are identical.
- Intentional deletions are honored, safely and reversibly (see 4.4).
- Duplicates area with previews and size-based "main file" recommendation.
- Attractive yet clear UI, fully Apple HIG and Liquid Glass.
- Manual sync first (with a preview of what will happen); engine prepared for automatic sync.
- Distributed outside the Mac App Store now; architecture must allow App Store submission later without rework.

**Non-goals (for v1)**
- Automatic/continuous sync (prepared, not built).
- Network/cloud sources, iOS/iPadOS, versioning/history, encryption.

**Anti-goals (failure even if it "works")**
- Any silent data loss or overwrite.
- Treating an unmounted disk or unreachable folder as "files were deleted".
- Deleting permanently instead of using the Trash.

## 3. Constraints

- macOS only, SwiftUI, latest Swift (Xcode 27.x, Swift 6.x), Swift concurrency. Minimum deployment target macOS 26 (Liquid Glass) — *builder's call, confirm*.
- App Sandbox + Hardened Runtime enabled from day one; user-selected folders accessed via security-scoped bookmarks. This keeps the App Store path open and is also notarization-friendly.
- All documentation, comments, and identifiers in American English; every file carries the copyright line; Swift files carry the standard header (see `CLAUDE.md`).

## 4. Behavior

### 4.1 Sync set
A **sync set** is a named group of 2+ root directories (bookmarked). Each set has its own snapshot (4.4) and settings.

### 4.2 Merge rules
- Every file and subfolder present in any root ends up in all roots. Nothing is overwritten.
- Same relative path, different content: the incoming file is added as `name-1.ext`, `name-2.ext`, … The source hash is compared with the same-named file and **all** of its suffixed variants; it is added only if it differs from all of them.
- Same hash, different names (same or different folders): both are kept so the roots end identical; the duplicate group appears in the Duplicates area.
- Ignored: `.DS_Store`, `._*`, `.Trash`, `.Spotlight-V100`, `.fseventsd`, and similar system files. Packages (`.app`, `.photoslibrary`, …) and symlinks are treated as single opaque items; GT Sync never descends into them.

### 4.3 Duplicates area
- Lists every file and every group of related files, in two sections:
  - **Same content** (identical hash, any name or folder): exact duplicates.
  - **Same name, different content** (a name plus its `-x` variants with different hashes): these are *different* files that collided on a name. The sync keeps them all (merge); this area is where the user decides what to do with each (most likely rename, but also keep, or remove).
- The "main" file of a group is the one with the **largest size on disk** (allocated size, not logical size); ties: shortest path, then oldest, then alphabetical. All other members are "duplicates" and what happens to them is **always the user's decision**; GT Sync only recommends.
- Actions per member: rename (applied in every root), keep, move to the Trash (from every folder that holds it). Nothing happens without confirmation.
- Selecting any file (source or destination) shows a preview (Quick Look).

### 4.4 Deletions and renames
- Each sync set stores a **snapshot** of the last synced state (relative path, hash, size, modification date).
- A path in the snapshot that is now missing on one side is a *pending deletion*. It goes into a **review queue**: per item the user chooses *Propagate* (move the file to the Trash in every other root) or *Restore* (copy it back). An optional "always propagate" setting exists per sync set.
- A file that disappears and reappears elsewhere with the same hash is a **rename**, not a deletion plus a new file; the rename is propagated.
- **Safety rule:** if a root is unmounted or unreachable, the sync for that set is aborted and reported. Absence of a root is never interpreted as deletion.

### 4.5 Manual sync
Flow: choose set → **scan** → **plan preview** (adds, renames, suffixed copies, pending deletions, duplicates, nothing destructive) → user confirms → execute → report.

### 4.6 Automatic sync (prepared, not built)
The engine separates planning from execution and hides file-system watching behind a protocol, so an FSEvents-based watcher can trigger the same plan/preview/execute pipeline later. Policy for automatic runs (e.g. never auto-propagate deletions) is deferred until the author decides.

## 5. Approaches considered

**Deletion handling** (chosen: C)
- A. App-only deletions; Finder deletions are restored — safest, but ignores the user's intent.
- B. Automatic propagation of all deletions — convenient, but one mistake vanishes everywhere.
- **C. Snapshot + review queue, Trash only** — respects intent, reversible. *Chosen by the author.*

**Project structure** (chosen: 1, builder's call)
- **1. App target + local Swift package `GTSyncCore`** for the engine (scan, hash, plan, execute, snapshot), UI in the app target. Engine is testable without UI. *Chosen.*
- 2. Everything in the app target — faster to start, harder to test, engine tangled with UI.
- 3. Generated project (XcodeGen/Tuist) — extra tool dependency for little benefit here.

## 6. Architecture (builder's calls)

- `GTSyncCore` (package): `Scanner` (enumerates roots, applies ignore rules), `Hasher` (SHA-256, streaming, size pre-filter, cache keyed by path+size+mtime), `SnapshotStore` (per sync set, on disk), `Planner` (pure function: roots + snapshots → `SyncPlan`), `Executor` (applies a plan; copies via temp file + atomic move; deletions via `trashItem`), `DuplicateIndex`, `RootWatcher` protocol (no implementation yet).
- App target: SwiftUI, `NavigationSplitView` (sync sets / files / duplicates / review queue), Quick Look previews, Liquid Glass styling via the `liquid-glass` skill.
- Concurrency: scanning/hashing off the main actor with structured concurrency; progress via `AsyncStream`.
- Tests: Swift Testing in `GTSyncCore` — suffix numbering, hash collisions with variants, rename detection, deletion queue, unmounted-root abort, ignore rules — using temporary directories.

## 7. Open items for the builder

- Exact snapshot storage format (suggested: SQLite or JSON in Application Support, one file per set).
- Large-file copy strategy and progress granularity.
- Handling of extended attributes, permissions, and timestamps when copying (suggested: preserve).
- App icon, naming of UI sections, onboarding.

## 8. Decisions made during implementation (2026-11-23)

- **Duplicates:** "same name, different content" groups (a name plus its `-x` variants) and "same content" groups are separate; the main file is the largest size on disk (allocated size), ties: shortest path, oldest, alphabetical. All other members are the user's decision (rename, keep, Trash).
- **Name collisions:** the first root of the set (the "Primary", reorderable) keeps the base name; other roots rename their existing file to a `-x` variant (a move, never an overwrite), then receive the primary's version.
- **Safety:** an unmounted, unreadable or different-volume root aborts the sync; a root that is empty while the sync memory is not (ghost mount) aborts until the user confirms ("Continue Anyway"), which treats it as a new disk. Copies go through a hidden temp file, are verified by SHA-256, and are never moved over an existing name. Paths that escape a root (`..`, absolute, symlinked folders) are refused.
- **Deletions:** only files are tracked; folder deletions are not (an emptied folder is recreated by the merge). Unresolved pending deletions are carried across every operation so they are never forgotten.
- **Not verified at runtime:** the visual look against the mockups (no display was available while building), keyboard shortcuts, Quick Look interaction. Hardened Runtime and sandbox entitlements were verified with an ad-hoc signed release build; Developer ID signing and notarization are not done.
- **Placeholders:** app icon (generated glyph on a blue-teal gradient; to be replaced via Icon Composer), tint (blue-teal), bundle id `com.gennarotangari.GTSync`.
