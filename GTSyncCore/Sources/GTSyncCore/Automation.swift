//
//  Automation.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation

/// How often a timer-driven automatic run is allowed.
public enum AutomationInterval: String, Codable, Sendable, CaseIterable {
    case off, minutes15, minutes30, hour, hours6

    /// `nil` when the timer is off.
    public var seconds: TimeInterval? {
        switch self {
        case .off: nil
        case .minutes15: 900
        case .minutes30: 1_800
        case .hour: 3_600
        case .hours6: 21_600
        }
    }
}

/// Per set: what may start an automatic run. Everything is off by default.
public struct AutomationSettings: Codable, Sendable, Equatable {
    /// Run (after a short quiet period) when something changes in one of the folders.
    public var watchChanges: Bool
    public var interval: AutomationInterval
    /// Run when a disk is mounted.
    public var onDiskMount: Bool

    public init(watchChanges: Bool = false, interval: AutomationInterval = .off, onDiskMount: Bool = false) {
        self.watchChanges = watchChanges
        self.interval = interval
        self.onDiskMount = onDiskMount
    }

    public static let off = AutomationSettings()

    public var isOff: Bool { self == .off }
}

public enum AutomationTrigger: Sendable {
    case change, timer, diskMounted
    /// The user asked for it (menu bar, a button): always allowed, even while automation is paused.
    case manual
}

public enum AutomationPolicy {
    public static func shouldRun(_ settings: AutomationSettings, trigger: AutomationTrigger,
                                 lastRun: Date?, now: Date, paused: Bool) -> Bool {
        if trigger == .manual { return true }
        guard !paused else { return false }
        switch trigger {
        case .manual: return true
        case .change: return settings.watchChanges
        case .diskMounted: return settings.onDiskMount
        case .timer:
            guard let seconds = settings.interval.seconds else { return false }
            guard let lastRun else { return true }
            return now.timeIntervalSince(lastRun) >= seconds
        }
    }

    /// What an unattended run may do: adds, copies, folders and renames. Removals are never
    /// automatic; the plan's pending deletions stay in the review queue.
    public static func safeOperations(in plan: SyncPlan) -> [SyncOperation] {
        plan.operations.filter { if case .trash = $0 { false } else { true } }
    }
}
