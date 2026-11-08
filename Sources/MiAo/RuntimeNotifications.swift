// Copyright (c) 2026 FanXeon@Poemcoder with Codex
import Foundation

enum MiAoRuntimeNotifications {
    static let buttonConfigurationChanged = Notification.Name(
        "app.remotevoice.mac.button-configuration-changed"
    )
    static let buttonActivity = Notification.Name("app.remotevoice.mac.button-activity")
    static let voiceConnectionModeChanged = Notification.Name(
        "app.remotevoice.mac.voice-connection-mode-changed"
    )

    static func postButtonConfigurationChanged() {
        DistributedNotificationCenter.default().postNotificationName(
            buttonConfigurationChanged,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    static func postButtonActivity(button: RemoteButton, isPressed: Bool) {
        DistributedNotificationCenter.default().postNotificationName(
            buttonActivity,
            object: nil,
            userInfo: ["button": button.rawValue, "phase": isPressed ? "down" : "up"],
            deliverImmediately: true
        )
    }

    static func postVoiceConnectionModeChanged() {
        DistributedNotificationCenter.default().postNotificationName(
            voiceConnectionModeChanged,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}
