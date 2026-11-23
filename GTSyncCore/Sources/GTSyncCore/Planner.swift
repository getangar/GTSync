//
//  Planner.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation

enum PathUtil {
    static func dir(_ p: String) -> String {
        guard let i = p.lastIndex(of: "/") else { return "" }
        return String(p[..<i])
    }
    static func name(_ p: String) -> String {
        guard let i = p.lastIndex(of: "/") else { return p }
        return String(p[p.index(after: i)...])
    }
    static func join(_ d: String, _ n: String) -> String { d.isEmpty ? n : d + "/" + n }
    static func depth(_ p: String) -> Int { p.isEmpty ? 0 : p.split(separator: "/").count }
}

/// Pure planner: roots (in priority order) plus the last snapshot -> operations.
/// The first root keeps the base name when different contents collide on a name.
public enum Planner {
    public static func plan(roots: [RootIndex], snapshot: Snapshot) -> SyncPlan {
        var resolver = SnapshotResolver(roots: roots, snapshot: snapshot)
        resolver.resolve()
        var builder = PlanBuilder(roots: resolver.roots)
        builder.planDirectories()
        builder.planOpaqueItems()
        builder.planFiles()
        var plan = builder.finish()
        plan.operations = resolver.operations + plan.operations
        plan.pendingDeletions = resolver.pendingDeletions
        return plan
    }
}

private struct Member {
    let idx: Int
    let root: Int
    let item: IndexedItem
}

private struct Family {
    var members: [Member] = []
    var baseName: String
    var hasBase = false
    var dirCanonical: String
}

private struct Move {
    let root: Int
    let from: String
    let to: String
}

private struct PendingCopy {
    let fromRoot: Int
    let fromPath: String
    let toRoot: Int
    let toPath: String
    let reason: CopyReason
}

private struct PlanBuilder {
    let roots: [RootIndex]
    private var items: [[String: IndexedItem]]
    private var dirActual: [[String: String]]
    private var firstDirName: [String: String] = [:]
    private var canonCache: [String: String] = [:]
    private var conflicts: Set<String> = []

    private var dirOps: [SyncOperation] = []
    private var copiesFirst: [SyncOperation] = []
    private var moves: [Move] = []
    private var copiesAfterRenames: [PendingCopy] = []

    init(roots: [RootIndex]) {
        self.roots = roots
        items = Array(repeating: [:], count: roots.count)
        dirActual = Array(repeating: [:], count: roots.count)
        var kinds: [String: Set<ItemKind>] = [:]
        for (r, root) in roots.enumerated() {
            for item in root.items {
                let key = NameKey.key(for: item.relativePath)
                items[r][key] = item
                kinds[key, default: []].insert(item.kind)
                if item.kind == .directory {
                    dirActual[r][key] = item.relativePath
                    if firstDirName[key] == nil { firstDirName[key] = PathUtil.name(item.relativePath) }
                }
            }
        }
        conflicts = Set(kinds.filter { $0.value.count > 1 }.keys)
    }

    // MARK: Paths

    private mutating func canonicalDir(_ path: String) -> String {
        if path.isEmpty { return "" }
        let key = NameKey.key(for: path)
        if let cached = canonCache[key] { return cached }
        let result = PathUtil.join(canonicalDir(PathUtil.dir(path)), firstDirName[key] ?? PathUtil.name(path))
        canonCache[key] = result
        return result
    }

    private func resolveDir(_ root: Int, _ canonical: String) -> String {
        if canonical.isEmpty { return "" }
        if let actual = dirActual[root][NameKey.key(for: canonical)] { return actual }
        return PathUtil.join(resolveDir(root, PathUtil.dir(canonical)), PathUtil.name(canonical))
    }

    private func underConflict(_ path: String) -> Bool {
        var current = path
        while !current.isEmpty {
            if conflicts.contains(NameKey.key(for: current)) { return true }
            current = PathUtil.dir(current)
        }
        return false
    }

    // MARK: Directories and opaque items

    mutating func planDirectories() {
        let keys = Set(dirActual.flatMap { $0.keys })
            .sorted { (PathUtil.depth($0), $0) < (PathUtil.depth($1), $1) }
        for key in keys where !conflicts.contains(key) {
            guard let owner = roots.indices.first(where: { dirActual[$0][key] != nil }) else { continue }
            let canonical = canonicalDir(dirActual[owner][key]!)
            if underConflict(PathUtil.dir(canonical)) { continue }
            for r in roots.indices where dirActual[r][key] == nil {
                dirOps.append(.createDirectory(root: roots[r].rootID, path: resolveDir(r, canonical)))
            }
        }
    }

    mutating func planOpaqueItems() {
        let keys = Set(items.flatMap { $0.filter { $0.value.kind == .package || $0.value.kind == .symlink }.keys }).sorted()
        for key in keys where !conflicts.contains(key) {
            guard let owner = roots.indices.first(where: { items[$0][key] != nil }), let item = items[owner][key] else { continue }
            let canonicalParent = canonicalDir(PathUtil.dir(item.relativePath))
            if underConflict(canonicalParent) { continue }
            for r in roots.indices where items[r][key] == nil {
                copiesFirst.append(.copy(from: roots[owner].rootID, fromPath: item.relativePath, to: roots[r].rootID,
                                         toPath: PathUtil.join(resolveDir(r, canonicalParent), PathUtil.name(item.relativePath)), reason: .add))
            }
        }
    }

    // MARK: Files

    mutating func planFiles() {
        var fileKeys = Set<String>()
        for r in items.indices { for (k, it) in items[r] where it.kind == .file { fileKeys.insert(k) } }

        var families: [String: Family] = [:]
        for r in roots.indices {
            let files = items[r].values.filter { $0.kind == .file }.sorted { $0.relativePath < $1.relativePath }
            for item in files {
                let dir = PathUtil.dir(item.relativePath), name = PathUtil.name(item.relativePath)
                let (rootName, idx) = FamilyClassifier.classify(name: name, dir: dir, fileKeys: fileKeys)
                let familyKey = NameKey.key(for: PathUtil.join(dir, rootName))
                var family = families[familyKey] ?? Family(baseName: rootName, dirCanonical: canonicalDir(dir))
                if idx == 0 && !family.hasBase { family.baseName = name; family.hasBase = true }
                family.members.append(Member(idx: idx, root: r, item: item))
                families[familyKey] = family
            }
        }
        for key in families.keys.sorted() {
            plan(family: families[key]!, familyKey: key)
        }
    }

    private mutating func plan(family: Family, familyKey: String) {
        if family.members.contains(where: { $0.item.hash == nil }) { return }
        if conflicts.contains(familyKey) || underConflict(family.dirCanonical) { return }
        if family.members.contains(where: { conflicts.contains(NameKey.key(for: $0.item.relativePath)) }) { return }

        let byIdx = Dictionary(grouping: family.members, by: \.idx)
        let idxs = byIdx.keys.sorted()
        func nameFor(_ idx: Int) -> String {
            idx == 0 ? family.baseName : SuffixNaming.variantName(family.baseName, index: idx)
        }

        // 1. Winner per index = hash of the first root holding it; the others are losers.
        var canon: [Int: String] = [:]
        var used = Set(idxs)
        for i in idxs { canon[i] = byIdx[i]![0].item.hash! }
        var home: [String: Int] = [:]
        for i in idxs where home[canon[i]!] == nil { home[canon[i]!] = i }

        // 2. Losers move to the index where their content already lives, or to a fresh one.
        var staying: [Int: [Int: String]] = [:]      // root -> idx -> hash
        for m in family.members where m.item.hash! == canon[m.idx]! { staying[m.root, default: [:]][m.idx] = m.item.hash! }
        var assigned: [Int: [Int: String]] = [:]
        var familyMoves: [Move] = []
        var movedMembers: [Int: [String: String]] = [:]  // root -> oldPath -> newPath
        func freshIndex() -> Int {
            var n = 1
            while used.contains(n) { n += 1 }
            used.insert(n)
            return n
        }
        for i in idxs {
            for m in byIdx[i]! where m.item.hash! != canon[i]! {
                let h = m.item.hash!
                var target: Int
                if let j = home[h], j != i,
                   staying[m.root]?[j] != h, assigned[m.root]?[j] == nil {
                    target = j
                } else {
                    target = freshIndex()
                    canon[target] = h
                    if home[h] == nil { home[h] = target }
                }
                assigned[m.root, default: [:]][target] = h
                familyMoves.append(Move(root: m.root, from: m.item.relativePath,
                                        to: PathUtil.join(resolveDir(m.root, family.dirCanonical), nameFor(target))))
                movedMembers[m.root, default: [:]][m.item.relativePath] = familyMoves.last!.to
            }
        }

        // 3. Every canonical (index, hash) must exist in every root.
        let distinctHashes = Set(family.members.compactMap(\.item.hash)).count
        let reason: CopyReason = distinctHashes > 1 ? .variant : .add
        var firstPhase: [SyncOperation] = []
        var secondPhase: [PendingCopy] = []
        for idx in canon.keys.sorted() {
            let hash = canon[idx]!
            for r in roots.indices {
                if staying[r]?[idx] == hash || assigned[r]?[idx] == hash { continue }
                let source = family.members.first { $0.item.hash == hash && $0.root != r }
                    ?? family.members.first { $0.item.hash == hash }!
                let destPath = PathUtil.join(resolveDir(r, family.dirCanonical), nameFor(idx))
                let destKey = NameKey.key(for: destPath)
                if let existing = items[r][destKey], existing.kind != .file { return }   // a folder is in the way
                if items[r][destKey] != nil {
                    secondPhase.append(PendingCopy(fromRoot: source.root, fromPath: source.item.relativePath,
                                                   toRoot: r, toPath: destPath, reason: reason))
                } else {
                    firstPhase.append(.copy(from: roots[source.root].rootID, fromPath: source.item.relativePath,
                                            to: roots[r].rootID, toPath: destPath, reason: reason))
                }
            }
        }
        copiesFirst += firstPhase
        copiesAfterRenames += secondPhase
        moves += familyMoves
        _ = movedMembers
    }

    // MARK: Assembly

    mutating func finish() -> SyncPlan {
        var ops = dirOps + copiesFirst
        var renamedTo: [String: String] = [:]     // "root|oldPath" -> newPath
        var tmpCounter = 0
        for r in roots.indices {
            var pending = moves.filter { $0.root == r }.map { (from: $0.from, to: $0.to) }
            for m in pending { renamedTo["\(r)|\(m.from)"] = m.to }
            while !pending.isEmpty {
                let fromKeys = Set(pending.map { NameKey.key(for: $0.from) })
                if let i = pending.firstIndex(where: { !fromKeys.contains(NameKey.key(for: $0.to)) }) {
                    let m = pending.remove(at: i)
                    ops.append(.rename(root: roots[r].rootID, from: m.from, to: m.to))
                } else {
                    // Rename cycle: park the first file under a temporary name.
                    let m = pending.removeFirst()
                    let tmp = PathUtil.join(PathUtil.dir(m.from), "\(SyncPlan.swapPrefix)\(r)-\(tmpCounter)")
                    tmpCounter += 1
                    ops.append(.rename(root: roots[r].rootID, from: m.from, to: tmp))
                    pending.append((from: tmp, to: m.to))
                }
            }
        }
        for c in copiesAfterRenames {
            let source = renamedTo["\(c.fromRoot)|\(c.fromPath)"] ?? c.fromPath
            ops.append(.copy(from: roots[c.fromRoot].rootID, fromPath: source, to: roots[c.toRoot].rootID,
                             toPath: c.toPath, reason: c.reason))
        }
        return SyncPlan(operations: ops, pendingDeletions: [])
    }
}
