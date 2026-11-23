//
//  AppModel.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
import GTSyncCore
import Observation

enum SetTab: String, CaseIterable, Identifiable {
    case overview, files, duplicates, review, history
    var id: String { rawValue }
}

enum SetStatus: Equatable {
    case inSync, needsReview, neverSynced, rootUnavailable
}

@MainActor @Observable
final class AppModel {
    private(set) var sets: [SyncSet] = []
    var selectedSetID: UUID?
    var selectedTab: SetTab = .overview
    var searchText = ""
    /// Pending deletions found by the last plan, per set (drives the "needs review" status).
    var pendingCounts: [UUID: Int] = [:]
    var lastError: String?

    // Sync flow (see SyncActions.swift)
    var phase: SyncPhase = .idle
    var lastScan: ScanSnapshot?
    var duplicateGroups: [DuplicateGroup] = []
    var lastPlan: SyncPlan?
    var scanSetID: UUID?
    var isRefreshing = false
    /// A user-approved action (restore, trash, rename) is running.
    var isPerforming = false
    var allowedEmptyRoots: [UUID: Set<RootID>] = [:]
    @ObservationIgnored var session: SyncSession?
    @ObservationIgnored var syncTask: Task<Void, Never>?
    @ObservationIgnored var refreshTask: Task<Void, Never>?
    @ObservationIgnored var makeEngine: (SyncSet, Set<RootID>) -> any SyncRunning

    private let setStore: SetStore
    private let snapshotStore: SnapshotStore
    private let historyStore: HistoryStore
    private let snapshotStatus: SnapshotStatusCache
    private(set) var historyRevision = 0
    private let bookmarks = BookmarkStore()

    init(setStore: SetStore, snapshotStore: SnapshotStore, historyStore: HistoryStore? = nil) {
        self.setStore = setStore
        self.snapshotStore = snapshotStore
        self.snapshotStatus = SnapshotStatusCache(
            stamp: { id in
                let url = snapshotStore.directory.appendingPathComponent("\(id.uuidString).json")
                return (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            },
            loadHasEntries: { id in !((try? snapshotStore.load(setID: id))?.entries.isEmpty ?? true) })
        self.historyStore = historyStore ?? HistoryStore(directory: snapshotStore.directory.appendingPathComponent("history", isDirectory: true))
        makeEngine = { set, allowEmpty in
            SyncEngine(set: set, store: snapshotStore, ignore: IgnoreSettings.rules(), allowEmptyRoots: allowEmpty)
        }
        do {
            sets = try setStore.load()
        } catch {
            lastError = error.localizedDescription
        }
        selectedSetID = sets.first?.id
    }

    static func live() -> AppModel {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GT Sync", isDirectory: true)
        return AppModel(setStore: .standard(),
                        snapshotStore: SnapshotStore(directory: support.appendingPathComponent("snapshots", isDirectory: true)))
    }

    var selectedSet: SyncSet? { sets.first { $0.id == selectedSetID } }

    /// True while anything that touches the folders (or rescans them) is in progress. Every entry
    /// point checks it, and the buttons are disabled meanwhile.
    var isBusy: Bool { !phase.isIdle || isRefreshing || isPerforming }

    // MARK: Sets

    @discardableResult
    func addSet(name: String) -> UUID {
        let set = SyncSet(name: name)
        sets.append(set)
        selectedSetID = set.id
        selectedTab = .overview
        persist()
        return set.id
    }

    func renameSet(_ id: UUID, to name: String) {
        mutate(id) { $0.name = name }
    }

    func deleteSet(_ id: UUID) {
        sets.removeAll { $0.id == id }
        pendingCounts[id] = nil
        try? FileManager.default.removeItem(at: snapshotFile(id))
        historyStore.remove(setID: id)
        if selectedSetID == id { selectedSetID = sets.first?.id }
        persist()
    }

    // MARK: Roots

    func addRoot(to setID: UUID, url: URL) {
        bookmarks.startAccess(to: url)
        let key = url.resolvingSymlinksInPath().standardizedFileURL.path
        mutate(setID) { set in
            guard !set.roots.contains(where: { $0.url.resolvingSymlinksInPath().standardizedFileURL.path == key }) else { return }
            set.roots.append(Root(displayName: url.lastPathComponent, url: url, volumeUUID: RootGuard.volumeUUID(of: url)))
        }
    }

    func removeRoot(_ rootID: RootID, from setID: UUID) {
        mutate(setID) { $0.roots.removeAll { $0.id == rootID } }
    }

    /// The first root is the primary: it keeps the base name when names collide.
    func moveRoots(in setID: UUID, from source: IndexSet, to destination: Int) {
        mutate(setID) { $0.roots.move(fromOffsets: source, toOffset: destination) }
    }

    func makePrimary(_ rootID: RootID, in setID: UUID) {
        mutate(setID) { set in
            guard let index = set.roots.firstIndex(where: { $0.id == rootID }) else { return }
            set.roots.move(fromOffsets: IndexSet(integer: index), toOffset: 0)
        }
    }

    // MARK: Status

    func unavailableRoots(in set: SyncSet) -> [Root] {
        // Without a scan count the guard never looks at the snapshot, so don't read it here.
        return set.roots.filter { RootGuard.check($0, snapshot: .empty, currentItemCount: nil) != nil }
    }

    func status(of set: SyncSet) -> SetStatus {
        if !unavailableRoots(in: set).isEmpty { return .rootUnavailable }
        if (pendingCounts[set.id] ?? 0) > 0 { return .needsReview }
        return snapshotStatus.hasEntries(set.id) ? .inSync : .neverSynced
    }

    // MARK: History

    func history(for setID: UUID) -> [HistoryEntry] {
        _ = historyRevision
        return (try? historyStore.load(setID: setID)) ?? []
    }

    func record(_ entry: HistoryEntry, for setID: UUID) {
        try? historyStore.append(entry, setID: setID)
        historyRevision += 1
    }

    // MARK: Helpers

    private func mutate(_ id: UUID, _ change: (inout SyncSet) -> Void) {
        guard let index = sets.firstIndex(where: { $0.id == id }) else { return }
        change(&sets[index])
        persist()
    }

    private func persist() {
        do { try setStore.save(sets) } catch { lastError = error.localizedDescription }
    }

    private func snapshotFile(_ id: UUID) -> URL {
        snapshotStore.directory.appendingPathComponent("\(id.uuidString).json")
    }
}
