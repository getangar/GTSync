//
//  Theme.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import AppKit
import SwiftUI

enum Theme {
    /// Blue-teal app tint (light / dark variants).
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.235, green: 0.765, blue: 0.820, alpha: 1)
            : NSColor(srgbRed: 0.039, green: 0.561, blue: 0.616, alpha: 1)
    })
}
