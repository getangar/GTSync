//
//  GlassBar.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import SwiftUI

/// Floating action bar (functional layer): Liquid Glass capsule pinned at the bottom of a screen.
/// Content above it stays plain; only this bar is glass.
struct GlassBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) { content }
                .padding(.vertical, 10)
                .padding(.leading, 20)
                .padding(.trailing, 12)
                .glassEffect(.regular, in: .capsule)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
    }
}
