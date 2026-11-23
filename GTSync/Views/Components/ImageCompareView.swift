//
//  ImageCompareView.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import AppKit
import ImageIO
import SwiftUI

/// Two versions of an image on top of each other, with a handle to reveal one or the other.
struct ImageCompareView: View {
    let leftURL: URL
    let rightURL: URL
    let leftTitle: LocalizedStringKey
    let rightTitle: LocalizedStringKey
    @State private var left: NSImage?
    @State private var right: NSImage?
    @State private var fraction: CGFloat = 0.5

    var body: some View {
        GeometryReader { geo in
            ZStack {
                picture(right)
                picture(left)
                    .mask(alignment: .leading) { Rectangle().frame(width: geo.size.width * fraction) }
                Rectangle().fill(.white).frame(width: 2)
                    .shadow(radius: 2)
                    .position(x: geo.size.width * fraction, y: geo.size.height / 2)
                Image(systemName: "arrow.left.and.right.circle.fill")
                    .font(.title).foregroundStyle(.white).shadow(radius: 3)
                    .position(x: geo.size.width * fraction, y: geo.size.height / 2)
            }
            .overlay(alignment: .topLeading) { tag(leftTitle).padding(8) }
            .overlay(alignment: .topTrailing) { tag(rightTitle).padding(8) }
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                fraction = min(max(value.location.x / max(geo.size.width, 1), 0), 1)
            })
        }
        .background(.black.opacity(0.06))
        .clipShape(.rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary) }
        .task(id: leftURL) { left = await Self.load(leftURL) }
        .task(id: rightURL) { right = await Self.load(rightURL) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Image comparison")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: fraction = min(fraction + 0.1, 1)
            case .decrement: fraction = max(fraction - 0.1, 0)
            @unknown default: break
            }
        }
    }

    @ViewBuilder private func picture(_ image: NSImage?) -> some View {
        if let image { Image(nsImage: image).resizable().scaledToFit() } else { ProgressView() }
    }

    private func tag(_ title: LocalizedStringKey) -> some View {
        Text(title).font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 3)
            .background(.ultraThinMaterial, in: .capsule)
    }

    /// A screen-sized version, decoded off the main thread (originals can be very large).
    private static func load(_ url: URL) async -> NSImage? {
        await Task.detached(priority: .userInitiated) { () -> NSImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600,
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }.value
    }
}
