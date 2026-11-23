//
//  Space.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation

public struct TreemapRect: Sendable, Equatable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var area: Double { width * height }

    public func overlapArea(with other: TreemapRect) -> Double {
        let w = min(x + width, other.x + other.width) - max(x, other.x)
        let h = min(y + height, other.y + other.height) - max(y, other.y)
        return w > 0 && h > 0 ? w * h : 0
    }
}

public struct TreemapTile: Sendable, Equatable {
    public let id: String
    public let rect: TreemapRect
}

/// Squarified treemap: tiles with areas proportional to the weights that fill `bounds` exactly.
public enum Treemap {
    public static func layout(weights: [(String, Double)], in bounds: TreemapRect) -> [TreemapTile] {
        let items = weights.filter { $0.1 > 0 }.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
        let total = items.reduce(0) { $0 + $1.1 }
        guard !items.isEmpty, bounds.area > 0 else { return [] }
        let scale = bounds.area / total
        var rest = items.map { ($0.0, $0.1 * scale) }[...]
        var rect = bounds
        var tiles: [TreemapTile] = []
        while !rest.isEmpty {
            let side = min(rect.width, rect.height)
            var row = [rest.removeFirst()]
            while let next = rest.first, worst(row.map(\.1) + [next.1], side) <= worst(row.map(\.1), side) {
                row.append(next)
                rest.removeFirst()
            }
            rect = place(row, in: rect, tiles: &tiles)
        }
        return tiles
    }

    private static func worst(_ areas: [Double], _ side: Double) -> Double {
        let sum = areas.reduce(0, +), big = areas.max()!, small = areas.min()!
        let s2 = side * side
        return max(s2 * big / (sum * sum), sum * sum / (s2 * small))
    }

    /// Lays the row along the shorter side and returns what is left of `rect`.
    private static func place(_ row: [(String, Double)], in rect: TreemapRect, tiles: inout [TreemapTile]) -> TreemapRect {
        let sum = row.reduce(0) { $0 + $1.1 }
        if rect.width >= rect.height {
            let w = sum / rect.height
            var y = rect.y
            for (id, area) in row {
                let h = area / w
                tiles.append(TreemapTile(id: id, rect: TreemapRect(x: rect.x, y: y, width: w, height: h)))
                y += h
            }
            return TreemapRect(x: rect.x + w, y: rect.y, width: rect.width - w, height: rect.height)
        }
        let h = sum / rect.width
        var x = rect.x
        for (id, area) in row {
            let w = area / h
            tiles.append(TreemapTile(id: id, rect: TreemapRect(x: x, y: rect.y, width: w, height: h)))
            x += w
        }
        return TreemapRect(x: rect.x, y: rect.y + h, width: rect.width, height: rect.height - h)
    }
}

/// One entry of the space map: a file or a folder with everything below it.
public struct SpaceNode: Sendable, Identifiable, Equatable {
    public var id: String { path }
    public let name: String
    public let path: RelativePath
    /// Size on disk, including everything below a folder.
    public let size: Int64
    /// Part of `size` held by files whose content exists more than once in the set.
    public let duplicateSize: Int64
    public let isFolder: Bool
}

public enum SpaceUsage {
    /// The direct children of `folder` ("" = the root), largest first.
    public static func children(of folder: RelativePath, in items: [IndexedItem], duplicateHashes: Set<String>) -> [SpaceNode] {
        let prefix = folder.isEmpty ? "" : folder + "/"
        var size: [String: Int64] = [:], duplicate: [String: Int64] = [:], folders: Set<String> = []
        for item in items where item.relativePath.hasPrefix(prefix) && item.relativePath != folder {
            let rest = item.relativePath.dropFirst(prefix.count)
            let name = String(rest.split(separator: "/", maxSplits: 1).first ?? "")
            guard !name.isEmpty else { continue }
            if rest.contains("/") || item.kind == .directory { folders.insert(name) }
            guard item.kind != .directory else { size[name, default: 0] += 0; continue }
            size[name, default: 0] += item.allocatedSize
            if let hash = item.hash, duplicateHashes.contains(hash) { duplicate[name, default: 0] += item.allocatedSize }
        }
        return size.map { name, bytes in
            SpaceNode(name: name, path: prefix + name, size: bytes, duplicateSize: duplicate[name] ?? 0,
                      isFolder: folders.contains(name))
        }.sorted { $0.size != $1.size ? $0.size > $1.size : $0.name < $1.name }
    }
}
