//
//  AutomationCoordinator.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import AppKit
import Foundation
import GTSyncCore

extension SyncSet {
    /// Changes when the set starts or stops needing a watcher, or its folders change.
    var watchSignature: String {
        automation.watchChanges ? roots.map(\.url.path).joined(separator: "|") : ""
    }
}

/// Connects what can wake a set up (file changes, the clock, a disk being mounted) to
/// `AppModel.runAutomatic`. The model decides whether a run is allowed; this only listens.
@MainActor final class AutomationCoordinator {
    private let model: AppModel
    private var watchers: [UUID: (signature: String, task: Task<Void, Never>)] = [:]
    private var debounces: [UUID: Task<Void, Never>] = [:]
    private var ticker: Task<Void, Never>?
    private var mountObserver: (any NSObjectProtocol)?

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        reconcile()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self else { return }
                await model.drainDeferredAutomation()
                for set in model.sets { await model.runAutomatic(set.id, trigger: .timer) }
            }
        }
        mountObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))               // let the disk settle
                guard let self else { return }
                for set in self.model.sets { await self.model.runAutomatic(set.id, trigger: .diskMounted) }
            }
        }
    }

    /// Starts, restarts or stops the file watchers so they match the sets as they are now.
    func reconcile() {
        let sets = model.sets
        for (id, watcher) in watchers where !sets.contains(where: { $0.id == id && $0.watchSignature == watcher.signature }) {
            watcher.task.cancel()
            watchers[id] = nil
        }
        for set in sets where !set.watchSignature.isEmpty && watchers[set.id] == nil {
            let id = set.id, roots = set.roots
            let task = Task { [weak self] in
                for await _ in FSEventsWatcher().events(for: roots) { self?.changed(id) }
            }
            watchers[id] = (set.watchSignature, task)
        }
    }

    /// Waits for a quiet moment so a burst of changes becomes one run.
    private func changed(_ id: UUID) {
        debounces[id]?.cancel()
        debounces[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self else { return }
            await model.runAutomatic(id, trigger: .change)
        }
    }
}
