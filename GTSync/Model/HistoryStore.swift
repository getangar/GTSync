//
//  HistoryStore.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation

struct HistoryEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var adds: Int
    var variants: Int
    var renames: Int
    var trashed: Int
    var failures: Int
    var cancelled: Bool
}

/// Past runs per sync set, newest first. Read-only in the UI; the Trash is the undo path.
struct HistoryStore {
    static let maxEntries = 200
    let directory: URL

    private func fileURL(_ setID: UUID) -> URL { directory.appendingPathComponent("\(setID.uuidString).json") }

    func load(setID: UUID) throws -> [HistoryEntry] {
        guard FileManager.default.fileExists(atPath: fileURL(setID).path) else { return [] }
        return try JSONDecoder().decode([HistoryEntry].self, from: Data(contentsOf: fileURL(setID)))
    }

    func append(_ entry: HistoryEntry, setID: UUID) throws {
        var entries = (try? load(setID: setID)) ?? []
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries { entries.removeLast(entries.count - Self.maxEntries) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: fileURL(setID), options: .atomic)
    }

    func remove(setID: UUID) { try? FileManager.default.removeItem(at: fileURL(setID)) }
}
