//
//  StatusLabel.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import SwiftUI

/// Status glyph for a sync set. Color is never the only signal: every case has a symbol and text.
struct StatusLabel: View {
    let status: SetStatus

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(color)
            .accessibilityLabel(text)
            .help(text)
    }

    private var symbol: String {
        switch status {
        case .inSync: "checkmark.circle.fill"
        case .needsReview: "exclamationmark.triangle.fill"
        case .neverSynced: "circle.dashed"
        case .rootUnavailable: "externaldrive.badge.xmark"
        }
    }

    private var color: Color {
        switch status {
        case .inSync: .green
        case .needsReview: .orange
        case .neverSynced: .secondary
        case .rootUnavailable: .red
        }
    }

    private var text: LocalizedStringKey {
        switch status {
        case .inSync: "In sync"
        case .needsReview: "Needs your review"
        case .neverSynced: "Never synced"
        case .rootUnavailable: "A folder is not available"
        }
    }
}
