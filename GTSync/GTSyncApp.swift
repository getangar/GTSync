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
    @State private var coordinator: AutomationCoordinator?

    var body: some Scene {
        WindowGroup(id: "main") {
            MainView()
                .environment(model)
                .task {
                    guard coordinator == nil else { return }
                    let started = AutomationCoordinator(model: model)
                    started.start()
                    coordinator = started
                }
                .onChange(of: model.automationSignature) { _, _ in coordinator?.reconcile() }
        }
        .defaultSize(width: 1100, height: 700)

        MenuBarExtra {
            MenuBarContent().environment(model)
        } label: {
            Image(systemName: model.menuBarSymbol)
        }

        Settings {
            SettingsView()
        }
    }
}
