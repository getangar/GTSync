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

    // Sync flow (see AppModel+Sync.swift)
    var phase: SyncPhase = .idle
    var lastScan: ScanSnapshot?
    var duplicateGroups: [DuplicateGroup] = []
    var lastPlan: SyncPlan?
    var scanSetID: UUID?
    var isRefreshing = false
    var allowedEmptyRoots: [UUID: Set<RootID>] = [:]
    @ObservationIgnored var session: SyncSession?
    @ObservationIgnored var syncTask: Task<Void, Never>?
    @ObservationIgnored var refreshTask: Task<Void, Never>?
    @ObservationIgnored var makeEngine: (SyncSet, Set<RootID>) -> any SyncRunning

    private let setStore: SetStore
    private let snapshotStore: SnapshotStore
    private let bookmarks = BookmarkStore()

    init(setStore: SetStore, snapshotStore: SnapshotStore) {
        self.setStore = setStore
        self.snapshotStore = snapshotStore
        makeEngine = { set, allowEmpty in
            SyncEngine(set: set, store: snapshotStore, allowEmptyRoots: allowEmpty)
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
        let snapshot = (try? snapshotStore.load(setID: set.id)) ?? .empty
        return set.roots.filter { RootGuard.check($0, snapshot: snapshot, currentItemCount: nil) != nil }
    }

    func status(of set: SyncSet) -> SetStatus {
        if !unavailableRoots(in: set).isEmpty { return .rootUnavailable }
        if (pendingCounts[set.id] ?? 0) > 0 { return .needsReview }
        let snapshot = (try? snapshotStore.load(setID: set.id)) ?? .empty
        return snapshot.entries.isEmpty ? .neverSynced : .inSync
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
