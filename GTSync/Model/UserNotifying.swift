//
//  UserNotifying.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
import UserNotifications

/// Where automatic runs report what they did (a local notification in the app, a recorder in tests).
@MainActor protocol UserNotifying: AnyObject {
    func notify(title: String, body: String)
}

@MainActor final class SystemNotifier: UserNotifying {
    private var asked = false

    func notify(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        if !asked {
            asked = true
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
