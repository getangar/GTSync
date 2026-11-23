//
//  Executor.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation

public struct OperationFailure: Sendable {
    public let operation: SyncOperation
    public let message: String

    public init(operation: SyncOperation, message: String) {
        self.operation = operation
        self.message = message
    }
}

public struct ExecutionReport: Sendable {
    public var completed: Int = 0
    public var failures: [OperationFailure] = []
    public var wasCancelled = false

    public init(completed: Int = 0, failures: [OperationFailure] = [], wasCancelled: Bool = false) {
        self.completed = completed
        self.failures = failures
        self.wasCancelled = wasCancelled
    }
}

public struct ExecutionEvent: Sendable {
    /// Operations processed so far (successful or failed).
    public let completed: Int
    public let total: Int
    public let currentPath: RelativePath

    public init(completed: Int, total: Int, currentPath: RelativePath) {
        self.completed = completed
        self.total = total
        self.currentPath = currentPath
    }
}

private enum ExecutorError: LocalizedError {
    case destinationExists, notEnoughSpace, nameTooLong, verificationFailed, unknownRoot, pathOutsideRoot

    var errorDescription: String? {
        switch self {
        case .destinationExists: "The destination already exists; nothing was overwritten."
        case .notEnoughSpace: "Not enough free space on the destination volume."
        case .nameTooLong: "The destination name is too long."
        case .verificationFailed: "The copy did not match the original and was discarded."
        case .unknownRoot: "Unknown folder."
        case .pathOutsideRoot: "The path points outside the synced folder and was refused."
        }
    }
}

/// Applies operations safely: copies go through a hidden temp file, are verified by hash and then
/// moved into place; nothing is ever overwritten; removals use the Trash. A failing operation is
/// recorded and the remaining ones still run.
public struct Executor: Sendable {
    public typealias Copier = @Sendable (URL, URL) throws -> Void

    private let roots: [RootID: Root]
    /// Copies `source` to `destination`. Replaceable so tests can simulate failures.
    public var copier: Copier = { try FileManager.default.copyItem(at: $0, to: $1) }
    /// Free bytes on the volume of a directory. Replaceable for tests.
    public var freeSpace: @Sendable (URL) -> Int64? = { url in
        (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
    }

    public init(roots: [Root]) {
        self.roots = Dictionary(uniqueKeysWithValues: roots.map { ($0.id, $0) })
    }

    public func execute(
        _ operations: [SyncOperation],
        progress: @Sendable (ExecutionEvent) -> Void
    ) async throws -> ExecutionReport {
        var report = ExecutionReport()
        for (index, operation) in operations.enumerated() {
            if Task.isCancelled {
                report.wasCancelled = true
                break
            }
            do {
                try perform(operation)
                report.completed += 1
            } catch {
                report.failures.append(OperationFailure(operation: operation, message: error.localizedDescription))
            }
            progress(ExecutionEvent(completed: index + 1, total: operations.count, currentPath: Self.path(of: operation)))
            await Task.yield()
        }
        return report
    }

    /// Deletes `.gtsync-*.tmp` leftovers of an interrupted run.
    public static func removeStrayTemps(in root: URL) {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return }
        for case let url as URL in walker where url.lastPathComponent.hasPrefix(".gtsync-") && url.pathExtension == "tmp" {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: Operations

    private func perform(_ operation: SyncOperation) throws {
        let fm = FileManager.default
        switch operation {
        case let .createDirectory(root, path):
            let url = try resolve(root, path)
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue { return }
            try fm.createDirectory(at: url, withIntermediateDirectories: false)

        case let .copy(fromRoot, fromPath, toRoot, toPath, _):
            try copy(from: resolve(fromRoot, fromPath), to: resolve(toRoot, toPath))

        case let .rename(root, from, to):
            let source = try resolve(root, from), target = try resolve(root, to)
            try checkName(target)
            guard !exists(target) else { throw ExecutorError.destinationExists }
            try fm.moveItem(at: source, to: target)

        case let .trash(root, path):
            try fm.trashItem(at: resolve(root, path), resultingItemURL: nil)
        }
    }

    private func copy(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        try checkName(destination)
        guard !exists(destination) else { throw ExecutorError.destinationExists }

        let attributes = try fm.attributesOfItem(atPath: source.path)
        let isRegular = (attributes[.type] as? FileAttributeType) == .typeRegular
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let directory = destination.deletingLastPathComponent()
        if isRegular, let free = freeSpace(directory), free < size { throw ExecutorError.notEnoughSpace }

        let temp = directory.appendingPathComponent(".gtsync-\(UUID().uuidString).tmp")
        do {
            try copier(source, temp)
            if isRegular, try FileHasher.sha256(of: source) != FileHasher.sha256(of: temp) {
                throw ExecutorError.verificationFailed
            }
            if let modified = attributes[.modificationDate] as? Date {
                try? fm.setAttributes([.modificationDate: modified], ofItemAtPath: temp.path)
            }
            try fm.moveItem(at: temp, to: destination)   // fails if the name appeared meanwhile
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
    }

    // MARK: Helpers

    /// Maps a root-relative path to a URL and refuses anything that could leave the root: absolute
    /// paths, `.`/`..`/empty components, and parents that resolve (through symlinks) outside the root.
    private func resolve(_ root: RootID, _ path: RelativePath) throws -> URL {
        guard let found = roots[root] else { throw ExecutorError.unknownRoot }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"),
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw ExecutorError.pathOutsideRoot
        }
        let url = found.url.appendingPathComponent(path)
        let rootPath = found.url.resolvingSymlinksInPath().standardizedFileURL.path
        let parentPath = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
        guard parentPath == rootPath || parentPath.hasPrefix(rootPath + "/") else {
            throw ExecutorError.pathOutsideRoot
        }
        return url
    }

    private func checkName(_ url: URL) throws {
        if url.lastPathComponent.utf8.count > SuffixNaming.maxNameBytes { throw ExecutorError.nameTooLong }
    }

    private func exists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil   // also true for dangling symlinks
    }

    private static func path(of operation: SyncOperation) -> RelativePath {
        switch operation {
        case let .createDirectory(_, path), let .trash(_, path): path
        case let .copy(_, _, _, toPath, _): toPath
        case let .rename(_, _, to): to
        }
    }
}
