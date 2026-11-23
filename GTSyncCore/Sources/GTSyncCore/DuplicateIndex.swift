//
//  DuplicateIndex.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation

public struct DuplicateMember: Sendable, Hashable {
    public let rootID: RootID
    public let relativePath: RelativePath
    public let allocatedSize: Int64
    public let modified: Date
    public let hash: String
}

public enum DuplicateKind: Sendable {
    /// Identical content under different names or folders.
    case exactContent
    /// A name plus its `-x` variants with different content: different files that collided on a name.
    case nameVariants
}

public struct DuplicateGroup: Identifiable, Sendable {
    public let id: String
    public let kind: DuplicateKind
    /// Every location (a file present in two roots counts twice).
    public let members: [DuplicateMember]
    /// Largest size on disk; ties: shortest path, oldest, alphabetical path.
    public let main: DuplicateMember
    /// Every location of every file that is not the main one. Always the user's decision.
    public let redundant: [DuplicateMember]

    /// Trash operations for the chosen members, in every root that holds the same file.
    public func removalOperations(of chosen: [DuplicateMember]) -> [SyncOperation] {
        var seen = Set<String>()
        var operations: [SyncOperation] = []
        for member in chosen {
            for location in locations(of: member) where seen.insert("\(location.rootID.rawValue)|\(location.relativePath)").inserted {
                operations.append(.trash(root: location.rootID, path: location.relativePath))
            }
        }
        return operations
    }

    /// Trash operations for every redundant member (the app's recommendation).
    public func removalOperations() -> [SyncOperation] { removalOperations(of: redundant) }

    /// Renames the member in every root that holds it. `nil` if the new name is empty, contains
    /// a slash, is too long, or already exists in the same folder of any root.
    public func renameOperations(member: DuplicateMember, newName: String, in roots: [RootIndex]) -> [SyncOperation]? {
        guard !newName.isEmpty, !newName.contains("/"), newName.utf8.count <= SuffixNaming.maxNameBytes else { return nil }
        let targetKey = NameKey.key(for: PathUtil.join(PathUtil.dir(member.relativePath), newName))
        for root in roots where root.items.contains(where: { NameKey.key(for: $0.relativePath) == targetKey }) {
            return nil
        }
        return locations(of: member).map {
            .rename(root: $0.rootID, from: $0.relativePath,
                    to: PathUtil.join(PathUtil.dir($0.relativePath), newName))
        }
    }

    private func locations(of member: DuplicateMember) -> [DuplicateMember] {
        let key = NameKey.key(for: member.relativePath)
        return members.filter { NameKey.key(for: $0.relativePath) == key && $0.hash == member.hash }
    }
}

public enum DuplicateIndex {
    public static func groups(for roots: [RootIndex]) -> [DuplicateGroup] {
        var members: [DuplicateMember] = []
        for root in roots {
            for item in root.items.sorted(by: { $0.relativePath < $1.relativePath }) where item.kind == .file {
                guard let hash = item.hash else { continue }
                members.append(DuplicateMember(rootID: root.rootID, relativePath: item.relativePath,
                                               allocatedSize: item.allocatedSize, modified: item.modified, hash: hash))
            }
        }
        var sizes: [String: Int64] = [:]
        for root in roots { for item in root.items where item.kind == .file { sizes["\(root.rootID.rawValue)|\(item.relativePath)"] = item.size } }

        var groups: [DuplicateGroup] = []

        // Same content under different paths (zero-byte files are never duplicates).
        let byHash = Dictionary(grouping: members.filter { (sizes["\($0.rootID.rawValue)|\($0.relativePath)"] ?? 0) > 0 }, by: \.hash)
        for (hash, list) in byHash where Set(list.map { NameKey.key(for: $0.relativePath) }).count >= 2 {
            groups.append(makeGroup(id: "hash:\(hash)", kind: .exactContent, members: list))
        }

        // Same name, different content.
        let fileKeys = Set(members.map { NameKey.key(for: $0.relativePath) })
        var families: [String: [DuplicateMember]] = [:]
        for member in members {
            let dir = PathUtil.dir(member.relativePath), name = PathUtil.name(member.relativePath)
            let (rootName, _) = FamilyClassifier.classify(name: name, dir: dir, fileKeys: fileKeys)
            families[NameKey.key(for: PathUtil.join(dir, rootName)), default: []].append(member)
        }
        for (key, list) in families where Set(list.map(\.hash)).count >= 2 {
            groups.append(makeGroup(id: "name:\(key)", kind: .nameVariants, members: list))
        }
        return groups.sorted { $0.id < $1.id }
    }

    private static func makeGroup(id: String, kind: DuplicateKind, members: [DuplicateMember]) -> DuplicateGroup {
        let main = members.min(by: isBetter)!
        let mainKey = NameKey.key(for: main.relativePath)
        let redundant = members.filter { !(NameKey.key(for: $0.relativePath) == mainKey && $0.hash == main.hash) }
        return DuplicateGroup(id: id, kind: kind, members: members, main: main, redundant: redundant)
    }

    /// Strict ordering where "better main" sorts first.
    private static func isBetter(_ x: DuplicateMember, _ y: DuplicateMember) -> Bool {
        if x.allocatedSize != y.allocatedSize { return x.allocatedSize > y.allocatedSize }
        if x.relativePath.count != y.relativePath.count { return x.relativePath.count < y.relativePath.count }
        if x.modified != y.modified { return x.modified < y.modified }
        if x.relativePath != y.relativePath { return x.relativePath < y.relativePath }
        return x.rootID.rawValue.uuidString < y.rootID.rawValue.uuidString
    }
}
