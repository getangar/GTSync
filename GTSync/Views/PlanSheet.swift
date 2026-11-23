//
//  PlanSheet.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import GTSyncCore
import SwiftUI

/// The sync sheet: plan preview, progress, report, or a plain-language failure.
struct PlanSheet: View {
    let set: SyncSet
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch model.phase {
            case let .planReady(plan): PlanContent(set: set, plan: plan)
            case let .running(event): RunningContent(event: event)
            case let .finished(report): ReportContent(set: set, report: report)
            case let .failed(failure): FailureContent(set: set, failure: failure)
            case .idle, .scanning: EmptyView()
            }
        }
        .padding(24)
        .frame(width: 560)
        .interactiveDismissDisabled(isRunning)
    }

    private var isRunning: Bool { if case .running = model.phase { true } else { false } }
}

private struct PlanContent: View {
    let set: SyncSet
    let plan: SyncPlan
    @Environment(AppModel.self) private var model

    var body: some View {
        let summary = plan.summary
        Text("Sync plan · \(set.name)").font(.title3.bold())
        if plan.isEmpty {
            Label("Everything is already in sync.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                line(summary.adds, "Files to add", "Copied to the folders that miss them", .blue)
                line(summary.variants, "Added as copies (-1, -2 …)", "Same name, different content: both versions are kept", .orange)
                line(summary.renames, "Renames to apply", "Same content under a new name", .primary)
                line(summary.directories, "Folders to create", nil, .primary)
                line(summary.pendingDeletions, "Pending deletions", "Decide in the Review tab. Nothing is removed now.", .orange)
                line(model.duplicateGroups.count, "Duplicate groups", "See the Duplicates tab", .primary)
            }
            if !plan.operations.isEmpty {
                DisclosureGroup("Show details") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(plan.operations.prefix(300).enumerated()), id: \.offset) { _, op in
                                Text(describe(op)).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                            }
                            if plan.operations.count > 300 {
                                Text("… and \(plan.operations.count - 300) more").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 160)
                }
            }
        }
        HStack {
            Text("Nothing is overwritten. Removals go to the Trash.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Cancel", role: .cancel) { model.cancelSync() }
                .keyboardShortcut(.cancelAction)
            Button(plan.operations.isEmpty ? "Mark as Synced" : "Start Sync") { model.confirmPlan() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private func line(_ count: Int, _ title: LocalizedStringKey, _ detail: LocalizedStringKey?, _ color: Color) -> some View {
        if count > 0 {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("\(count)").font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(color).frame(width: 54, alignment: .trailing)
                VStack(alignment: .leading) {
                    Text(title)
                    if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
            }
            .padding(.vertical, 6)
        }
    }

    private func describe(_ op: SyncOperation) -> String {
        func name(_ id: RootID) -> String { set.roots.first { $0.id == id }?.displayName ?? "?" }
        switch op {
        case let .createDirectory(root, path): return "Create folder  \(name(root)) / \(path)"
        case let .copy(from, fromPath, to, toPath, _): return "Copy  \(name(from)) / \(fromPath)  →  \(name(to)) / \(toPath)"
        case let .rename(root, from, to): return "Rename  \(name(root)) / \(from)  →  \(to)"
        case let .swap(root, first, second): return "Swap names  \(name(root)) / \(first)  ⇄  \(second)"
        case let .trash(root, path, _): return "Move to Trash  \(name(root)) / \(path)"
        }
    }
}

private struct RunningContent: View {
    let event: ExecutionEvent?
    @Environment(AppModel.self) private var model

    var body: some View {
        Text("Syncing…").font(.title3.bold())
        if let event {
            ProgressView(value: Double(event.completed), total: Double(max(event.total, 1)))
            Text("\(event.completed) of \(event.total)").font(.callout).foregroundStyle(.secondary)
            Text(event.currentPath).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
        } else {
            ProgressView()
        }
        HStack {
            Spacer()
            Button("Cancel", role: .cancel) { model.cancelSync() }
        }
    }
}

private struct ReportContent: View {
    let set: SyncSet
    let report: ExecutionReport
    @Environment(AppModel.self) private var model

    var body: some View {
        Text(report.wasCancelled ? "Sync stopped" : "Sync finished").font(.title3.bold())
        Label("\(report.completed) operations done", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        if !report.failures.isEmpty {
            Label("\(report.failures.count) could not be done", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(report.failures.enumerated()), id: \.offset) { _, failure in
                        Text(failure.message).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
        }
        HStack {
            Spacer()
            if (model.pendingCounts[set.id] ?? 0) > 0 {
                Button("Open Review") { model.selectedTab = .review; model.dismissSync() }
            }
            Button("Done") { model.dismissSync() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
    }
}

private struct FailureContent: View {
    let set: SyncSet
    let failure: SyncFailure
    @Environment(AppModel.self) private var model

    var body: some View {
        Label(isAfterRun ? "Sync did not finish" : "Sync did not start", systemImage: "exclamationmark.octagon.fill")
            .font(.title3.bold()).foregroundStyle(.red)
        Text(message)
        if isAfterRun {
            Text("Some changes may already have been applied. Scan again to see the current state.")
                .font(.callout).foregroundStyle(.secondary)
        } else {
            Text("Nothing was changed.").font(.callout).foregroundStyle(.secondary)
        }
        HStack {
            Spacer()
            if case let .root(.suspiciouslyEmpty(id)) = failure {
                Button("Continue Anyway") { model.continueWithEmptyRoot(id, in: set.id) }
            }
            Button("OK") { model.dismissSync() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var isAfterRun: Bool { if case .afterRun = failure { true } else { false } }

    private var message: LocalizedStringKey {
        func name(_ id: RootID) -> String { set.roots.first { $0.id == id }?.displayName ?? "A folder" }
        switch failure {
        case let .root(.missing(id)): return "\(name(id)) is not connected."
        case let .root(.notReadable(id)): return "\(name(id)) cannot be read. Check its permissions."
        case let .root(.volumeChanged(id)): return "\(name(id)) is now on a different disk than before."
        case let .root(.suspiciouslyEmpty(id)):
            return "\(name(id)) is empty, but it used to contain files. If its disk is not mounted, stop here. If it is a new disk, you can continue: GT Sync will copy your files into it, and nothing is deleted."
        case let .other(text): return LocalizedStringKey(text)
        case let .afterRun(text): return "Something went wrong while syncing: \(text)"
        }
    }
}
