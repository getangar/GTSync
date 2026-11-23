//
//  StageItem.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
import GTSyncCore
import UniformTypeIdentifiers

/// One step of a running sync, translated for the live stage: what happened, to which file,
/// and between which folders (as positions in the set's folder list).
struct StageItem: Identifiable, Equatable {
    enum Kind { case copy, variant, rename, swap, folder, trash }

    let id: Int
    let kind: Kind
    let fileName: String
    let sourceIndex: Int?
    let destinationIndex: Int?

    init(event: ExecutionEvent, roots: [Root]) {
        func index(_ id: RootID) -> Int? { roots.firstIndex { $0.id == id } }
        id = event.completed
        fileName = (event.currentPath as NSString).lastPathComponent
        switch event.operation {
        case let .copy(from, _, to, _, reason):
            kind = reason == .variant ? .variant : .copy
            sourceIndex = index(from)
            destinationIndex = index(to)
        case let .rename(root, _, _):
            (kind, sourceIndex, destinationIndex) = (.rename, index(root), index(root))
        case let .swap(root, _, _):
            (kind, sourceIndex, destinationIndex) = (.swap, index(root), index(root))
        case let .createDirectory(root, _):
            (kind, sourceIndex, destinationIndex) = (.folder, index(root), index(root))
        case let .trash(root, _, _):
            (kind, sourceIndex, destinationIndex) = (.trash, index(root), index(root))
        }
    }
}

/// Small helpers shared by the compare and space views.
enum CompareSupport {
    static func isImage(_ url: URL) -> Bool {
        guard !url.pathExtension.isEmpty, let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    static func formatted(bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
