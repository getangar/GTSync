//
//  SyncStageView.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import GTSyncCore
import SwiftUI

/// The running sync, shown as it happens: the folders are stations, the file being processed
/// travels from its source to its destination, and a log keeps the latest steps readable.
struct SyncStageView: View {
    let set: SyncSet
    let event: ExecutionEvent?
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var chipFraction: CGFloat = 0.5
    @State private var arrivedIndex: Int?

    private var items: [StageItem] { model.recentEvents.map { StageItem(event: $0, roots: set.roots) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            stage
            log
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.cancelSync() }
            }
        }
        .onChange(of: event?.completed) { _, _ in advance() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Syncing…").font(.title3.bold())
                Text("Following every step. Nothing is overwritten.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let event {
                Gauge(value: Double(event.completed), in: 0...Double(max(event.total, 1))) {
                    Text("Progress")
                } currentValueLabel: {
                    Text("\(event.completed)").contentTransition(.numericText()).monospacedDigit()
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(Theme.accent)
                .accessibilityValue("\(event.completed) of \(event.total)")
                Text("of \(event.total)").font(.callout).foregroundStyle(.secondary).monospacedDigit()
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    // MARK: Stage

    private var stage: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                GlassEffectContainer(spacing: 16) {
                    HStack(spacing: 14) {
                        ForEach(Array(set.roots.enumerated()), id: \.element.id) { index, root in
                            station(root, index: index)
                        }
                    }
                }
                lane(width: geo.size.width)
                if let item = items.last { chip(item).position(x: chipFraction * geo.size.width, y: 118) }
            }
        }
        .frame(height: 140)
    }

    private func station(_ root: Root, index: Int) -> some View {
        let arrived = arrivedIndex == index
        return VStack(spacing: 6) {
            Image(systemName: "externaldrive.fill").font(.title2).foregroundStyle(Theme.accent)
            Text(root.displayName).font(.callout.weight(.semibold)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 78)
        .padding(.horizontal, 8)
        .glassEffect(.regular.tint(arrived ? Theme.accent.opacity(0.35) : nil), in: .rect(cornerRadius: 18))
        .scaleEffect(arrived && !reduceMotion ? 1.05 : 1)
        .accessibilityElement(children: .combine)
    }

    private func lane(width: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: width * 0.5 / CGFloat(max(set.roots.count, 1)), y: 118))
            path.addLine(to: CGPoint(x: width * (1 - 0.5 / CGFloat(max(set.roots.count, 1))), y: 118))
        }
        .stroke(.quaternary, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 6]))
    }

    private func chip(_ item: StageItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol(item.kind))
            Text(item.fileName).lineLimit(1).frame(maxWidth: 190)
        }
        .font(.callout)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
        .accessibilityHidden(true)
    }

    /// Puts the chip at the source and slides it to the destination; the destination "lands".
    private func advance() {
        guard let item = items.last else { return }
        let count = CGFloat(max(set.roots.count, 1))
        func x(_ index: Int?, fallback: CGFloat) -> CGFloat { index.map { (CGFloat($0) + 0.5) / count } ?? fallback }
        let destination = x(item.destinationIndex, fallback: chipFraction)
        guard !reduceMotion else {
            chipFraction = destination
            arrivedIndex = item.destinationIndex
            return
        }
        var jump = Transaction(animation: nil)
        jump.disablesAnimations = true
        withTransaction(jump) { chipFraction = x(item.sourceIndex, fallback: chipFraction) }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(30))
            withAnimation(.smooth(duration: 0.55), completionCriteria: .logicallyComplete) {
                chipFraction = destination
            } completion: {
                withAnimation(.spring(duration: 0.35, bounce: 0.4)) { arrivedIndex = item.destinationIndex }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    withAnimation(.smooth) { arrivedIndex = nil }
                }
            }
        }
    }

    // MARK: Log

    private var log: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.reversed().enumerated()), id: \.element.id) { position, item in
                row(item).opacity(1 - Double(position) * 0.09)
                    .transition(reduceMotion ? .identity : .asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 8 * 24, alignment: .topLeading)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: items.map(\.id))
        .clipped()
    }

    private func row(_ item: StageItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol(item.kind)).frame(width: 18).foregroundStyle(color(item.kind))
            Text(verb(item.kind)).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
            Text(item.fileName).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            Text(route(item)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .font(.callout)
        .frame(height: 20)
    }

    private func route(_ item: StageItem) -> String {
        func name(_ index: Int?) -> String { index.map { set.roots[$0].displayName } ?? "" }
        switch item.kind {
        case .copy, .variant: return "\(name(item.sourceIndex)) → \(name(item.destinationIndex))"
        default: return name(item.destinationIndex)
        }
    }

    private func symbol(_ kind: StageItem.Kind) -> String {
        switch kind {
        case .copy: "doc.on.doc"
        case .variant: "doc.badge.plus"
        case .rename: "pencil"
        case .swap: "arrow.left.arrow.right"
        case .folder: "folder.badge.plus"
        case .trash: "trash"
        }
    }

    private func color(_ kind: StageItem.Kind) -> Color {
        switch kind {
        case .copy, .folder: Theme.accent
        case .variant: .orange
        case .rename, .swap: .primary
        case .trash: .red
        }
    }

    private func verb(_ kind: StageItem.Kind) -> LocalizedStringKey {
        switch kind {
        case .copy: "Copied"
        case .variant: "Kept both"
        case .rename: "Renamed"
        case .swap: "Swapped names"
        case .folder: "Created folder"
        case .trash: "Moved to Trash"
        }
    }
}
