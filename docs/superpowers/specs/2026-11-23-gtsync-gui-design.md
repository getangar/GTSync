# GT Sync — GUI Design

(c)Copyright 2026 by Gennaro Eduardo Tangari.

Date: 2026-11-23 · Status: **draft, awaiting approval** · Companion to `2026-11-23-gtsync-design.md`

## 1. Intent

The interface must make a risky-sounding task (merging disks) feel **safe, legible, and calm**. The user should always know three things at a glance: what will happen, what has happened, and that nothing destructive occurs without their explicit confirmation. It should look attractive and unmistakably native: a standard macOS window, system typography, SF Symbols, and Liquid Glass used with restraint.

## 2. Principles

1. **Content first, glass for chrome.** Liquid Glass is applied to the navigation and control layer (sidebar, toolbar, floating action bars, badges). File lists, previews, and tables stay on standard system surfaces so they remain readable. No glass on glass.
2. **Preview before action.** Every sync and every removal is preceded by a plan the user can read and, for files, preview.
3. **Destructive actions are visibly different** (confirmation sheet, "Move to Trash" wording, red role) and always reversible via the Trash.
4. **Never rely on color alone.** Every status has an SF Symbol and a text label.
5. **Native first.** `NavigationSplitView`, `Table`, `inspector`, `Quick Look`, standard toolbar items, system colors; custom views only where the product needs them.

## 3. Window structure

One main window, three regions, plus a trailing inspector:

```
┌──────────────────────────────────────────────────────────────────────────┐
│ ● ● ●   GT Sync                    [ 🔍 Search files ]      [ ⟳ Sync… ]  │  toolbar (glass)
├───────────────┬───────────────────────────────────────┬──────────────────┤
│ SYNC SETS     │  Photos Backup                        │  INSPECTOR       │
│ ▸ Photos ✓    │  ┌ Overview │ Files │ Duplicates 12 │ │  ┌────────────┐  │
│   Work Docs ⚠ │  │ Review 3 │ History               │ │  │  preview   │  │
│   Archive  ○  │  └───────────────────────────────────┘ │  │ (Quick Look)│ │
│               │                                       │  └────────────┘  │
│ ＋ New Set    │   (content of the selected tab)       │  name, size,     │
│               │                                       │  hash, present   │
│ ⚙ Settings    │                                       │  in: ● ● ○       │
└───────────────┴───────────────────────────────────────┴──────────────────┘
```

- **Sidebar:** the list of sync sets, each with a status glyph (✓ in sync, ⚠ needs review, ○ never synced, ⛔ root unavailable). "New Set" at the bottom; Settings opens the standard Settings scene.
- **Content:** a segmented tab bar for the selected set: *Overview, Files, Duplicates, Review, History*. Badges show counts (duplicate groups, pending deletions).
- **Inspector:** shows the selected file (preview, details); hidden when nothing is selected or on tabs that don't need it. Toggle with the toolbar inspector button.
- **Toolbar:** search field, the primary **Sync…** button (the only tinted control), progress indicator while running.

## 4. Screens

### 4.1 Overview (per sync set)

Roots are shown as large **cards**, one per directory, arranged in a flow. Each card shows disk icon and name, path, free space, a live "mounted / unavailable" state, and file count and size after the last scan.

```
   ┌─────────────────────┐        ⇄        ┌─────────────────────┐
   │ 💽 Photos SSD        │                 │ 💽 Backup HDD        │
   │ /Volumes/Photos      │                 │ /Volumes/Backup      │
   │ 48,210 items · 312GB │                 │ 47,950 items · 305GB │
   │ ● Mounted            │                 │ ● Mounted            │
   └─────────────────────┘                 └─────────────────────┘

   Last sync: today 10:42  ·  3 pending deletions  ·  12 duplicate groups
                           [  Sync…  ]
```

A root that is unavailable shows a ⛔ state and disables Sync with an explanation ("Backup HDD is not connected. Nothing will be changed."), reflecting the safety rule. The cards sit in a `GlassEffectContainer` and may morph slightly when a root is added or removed.

### 4.2 Sync flow: scan → plan preview → confirm → progress

Pressing **Sync…** starts a scan (progress in the toolbar), then opens the **Plan** sheet:

```
┌ Sync plan — Photos Backup ───────────────────────────────┐
│  ＋ 214 files to add          (Photos → Backup: 190,       │
│                                Backup → Photos: 24)        │
│  ⧉  6 added as copies (-1, -2…)   different content       │
│  ↪  9 renames to apply                                     │
│  🗑  3 pending deletions  → review in the Review tab       │
│  ⧉ 12 duplicate groups    → see the Duplicates tab         │
│                                                            │
│  ▸ Show details  (expandable, per category, with preview)  │
│                                                            │
│  Nothing is overwritten. Deletions move to the Trash.      │
│                         [ Cancel ]   [ Start sync ]        │
└────────────────────────────────────────────────────────────┘
```

During execution the sheet becomes a progress view (current file, throughput, overall bar) with **Pause/Cancel**; afterwards it becomes a short report (counts, any errors, "Open Review"). Pending deletions are **never** executed from this sheet; they live in the Review tab.

### 4.3 Files

A `Table` of every item across all roots (flat or hierarchical toggle):

| Name | In | Size | Modified | Status |
|---|---|---|---|---|
| `IMG_0412.jpg` | ● ● ● | 4.2 MB | … | ✓ Synced |
| `report-1.pdf` | ● ○ ● | 1.1 MB | … | ⧉ Variant of `report.pdf` |

- The **In** column shows one dot per root (filled = present), with a tooltip naming each root.
- Filters: All, Not yet synced, Variants (`-x`), Duplicates, Renamed. Sort and column customization are standard.
- Selecting a row fills the inspector with the preview and details (full path per root, size, SHA-256, dates).

### 4.4 Duplicates

Left: list of **duplicate groups**. Right: the selected group.

```
┌ Groups ────────────┬ IMG_0412.jpg  (4 copies · 3 redundant) ─────────────┐
│ ▸ IMG_0412.jpg  4  │  ★ Main (largest)    Photos/2024/IMG_0412.jpg  4.2MB │
│   budget.xlsx   2  │  ○ Duplicate         Backup/2024/IMG_0412.jpg  4.2MB │
│   clip.mov      3  │  ○ Duplicate         Photos/old/foto.jpg       4.2MB │
│                    │  ○ Duplicate         Backup/old/IMG_01.jpg     4.2MB │
│                    │                                                       │
│                    │   [ preview of main ]   [ preview of selected ]       │
│                    │                                                       │
│                    │   Recommended: move 3 duplicates to the Trash         │
│                    │        [ Keep all ]   [ Review…  ▾ ]  [ Remove 3… ]   │
└────────────────────┴──────────────────────────────────────────────────────┘
```

- The list has two sections: **Same content** and **Same name, different content**. In the second, members are different files that collided on a name; per member the user can **Rename…** (applied in every root), **Keep**, or **Move to Trash**. Removal there asks for an extra confirmation because the content differs.
- The ★ **Main** file is the one with the largest size on disk (allocated size). Ties: shortest path, then oldest, then alphabetical. All others are duplicates the user decides about.
- Two previews side by side let the user compare the main file with any duplicate (the "easy judgment" requirement).
- **Remove N…** opens a confirmation sheet listing exactly which files, in which roots, will go to the Trash; nothing happens until confirmed. A bulk action "Review all recommendations" walks through groups one by one.
- Nothing is removed or renamed without an explicit confirmation sheet.

### 4.5 Review (pending deletions)

A list of files detected as deleted on one side, each with the preview and two clear choices:

```
┌ Pending deletions (3) ──────────────────────────────────────────────────┐
│ 🗑 contract.pdf   deleted in Photos SSD · still in Backup HDD           │
│                                    [ Restore ]   [ Propagate to Trash ] │
│ 🗑 old-notes.txt  deleted in Backup HDD · still in Photos SSD           │
│                                    [ Restore ]   [ Propagate to Trash ] │
│ ──                                                                      │
│              [ Restore all ]   [ Propagate all to Trash ]               │
└─────────────────────────────────────────────────────────────────────────┘
```

A per-set switch "Always propagate deletions" lives in the set's settings, with a warning explaining its effect.

### 4.6 History

A chronological list of past syncs with counts and a drill-down into what changed. Read-only; the Trash is the undo path for removals.

### 4.7 Settings

Standard Settings scene: *General* (default behavior, launch at login later), *Ignore rules* (the built-in list plus user additions), *Sync sets* defaults, *About*. Per-set options (name, roots, always-propagate) are edited from the set's sidebar context menu or Overview.

### 4.8 Menu bar item (prepared, not built)

A future `MenuBarExtra` will show status and pause/resume for automatic sync. v1 ships without it, but the app model (`SyncCoordinator` with observable status) is built so it can be added without restructuring.

## 5. Liquid Glass usage

- **Where:** toolbar and sidebar (system-provided glass for free), the floating action bars at the bottom of Duplicates and Review, status badges, and the root cards' container. The primary **Sync…** button uses the prominent glass button style with the app tint.
- **Where not:** tables, previews, text-heavy sheets (they use standard materials), and never glass layered on glass.
- Use `GlassEffectContainer` to group nearby glass elements so they blend and morph together; keep morphing subtle (adding a root card, appearing action bar).
- Respect **Reduce Transparency** and **Increase Contrast** automatically; verify contrast of text over glass in both appearances.
- Implementation must consult the `liquid-glass` skill for the exact current APIs on macOS 26+.

## 6. Look and feel

- **Appearance:** light and dark, system accent color respected; one app tint (proposed: a calm blue-teal) reserved for the primary action and selection emphasis.
- **Status colors (always paired with symbol + text):** green synced, blue pending/in progress, orange needs review, red error/destructive, gray unavailable.
- **Typography:** system fonts only; monospaced for hashes and paths.
- **Symbols:** SF Symbols (e.g. `externaldrive`, `arrow.left.arrow.right`, `doc.on.doc`, `trash`, `star.fill`), with symbol effects for progress and completion kept brief.
- **Motion:** short, purposeful; respects Reduce Motion.
- **Empty states:** friendly and instructive ("Add two or more folders to start"), using `ContentUnavailableView`.

## 7. Accessibility and input

- Full VoiceOver labels (status glyphs and root dots have text equivalents); keyboard navigation everywhere; shortcuts: ⌘N new set, ⌘R scan/sync, ⌘⌥I inspector, Space for Quick Look, ⌘⌫ on a selected duplicate to mark for removal.
- Window resizable with a sensible minimum size; sidebar collapsible; drag-and-drop of folders from Finder onto a sync set to add a root.

## 8. Approaches considered

- **A. Single-window split view with tabs per sync set (chosen, builder's call).** Familiar (Mail/Photos-like), scales to many sets, keeps the inspector consistent.
- B. Wizard-style linear flow (pick folders → sync → done). Simple, but poor for the ongoing duplicates/review work and for automatic sync later.
- C. Menu-bar-only utility. Fits automatic sync, but cannot host the rich duplicates and preview experience.

## 9. Open items

- UI languages: English source strings with an Italian localization via String Catalog? *(proposed yes; to confirm)*
- Final app tint and app icon.
- Tie-break rule for "main" file when sizes are equal (see 4.4).
- Whether "Always propagate deletions" should exist at all in v1 or wait for the automatic-sync discussion.
