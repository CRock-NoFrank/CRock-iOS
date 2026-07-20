//
//  AppIntent.swift
//  CRockWidget
//
//  Created by 나현흠 on 8/9/25.
//

import WidgetKit
import AppIntents
import UserNotifications

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Configuration" }
    static var description: IntentDescription { "This is an example widget." }

    // An example configurable parameter.
    @Parameter(title: "Favorite Emoji", default: "😃")
    var favoriteEmoji: String
}

struct ToggleAlarmIntent: AppIntent {
    static var title: LocalizedStringResource { "Toggle Alarm" }
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupID)
        let currentValue = defaults?.bool(forKey: "isAlarmEnabled") ?? false
        let nextValue = !currentValue
        defaults?.set(nextValue, forKey: "isAlarmEnabled")
        defaults?.synchronize()

        if !nextValue {
            let center = UNUserNotificationCenter.current()
            center.removeAllPendingNotificationRequests()
            center.removeAllDeliveredNotifications()
        }

        WidgetCenter.shared.reloadTimelines(ofKind: "CRockWidget")
        return .result()
    }
}
