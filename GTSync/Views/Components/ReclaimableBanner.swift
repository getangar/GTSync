//
//  ReclaimableBanner.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import SwiftUI

/// A number that counts up to its value (SwiftUI interpolates `value` frame by frame).
struct CountingBytes: View, Animatable {
    nonisolated var value: Double
    nonisolated var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(CompareSupport.formatted(bytes: Int64(value))).monospacedDigit()
    }
}

/// "You can free 14.2 GB": the space held by redundant copies, as a large friendly number.
struct ReclaimableBanner: View {
    let bytes: Int64
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text("You can free").font(.callout).foregroundStyle(.secondary)
                CountingBytes(value: shown)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
            }
            Spacer(minLength: 0)
            Text("Held by copies that have the same content as a main file. You decide what to remove.")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: 240, alignment: .trailing)
        }
        .padding(16)
        .background(.background.secondary, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You can free \(CompareSupport.formatted(bytes: bytes))")
        .onAppear { update() }
        .onChange(of: bytes) { _, _ in update() }
    }

    private func update() {
        if reduceMotion { shown = Double(bytes) } else { withAnimation(.easeOut(duration: 0.9)) { shown = Double(bytes) } }
    }
}
