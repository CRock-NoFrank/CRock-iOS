//
//  AlarmIntents.swift
//  T8-NoFrank
//
//  Created by JiJooMaeng on 2/10/26.
//

import Foundation

#if canImport(AlarmKit)
import AppIntents
import AlarmKit

@available(iOS 26.0, *)
struct StopAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "알람 정지"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            AppRouter.shared.navigate(.breakingStone)
        }
        return .result()
    }
}
#endif

extension Notification.Name {
    static let alarmDismissed = Notification.Name("alarmDismissed")
}
