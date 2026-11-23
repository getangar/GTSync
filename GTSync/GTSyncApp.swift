//
//  GTSyncApp.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import SwiftUI

@main
struct GTSyncApp: App {
    @State private var model = AppModel.live()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(model)
        }
        .defaultSize(width: 1100, height: 700)

        Settings {
            SettingsView()
        }
    }
}
