//
//  NotificationExtension.swift
//  T8-NoFrank
//
//  Created by 문창재 on 8/9/25.
//

import SwiftUI
import UserNotifications

//MARK: -- 노티 배너 눌렀을 때 로직
extension NotificationDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {

        // ✅ 앱이 보낸 알림 전부 제거
        center.removeAllDeliveredNotifications()  // 이미 온 알림 삭제

        print("알림 제거 완료")

        let id = response.notification.request.identifier

        // 종료 경고 노티는 홈으로 이동
        if id == "appTerminationWarning" {
            Task { @MainActor in
                AppRouter.shared.navigate(.home)
            }
        } else {
            // burst 노티 또는 일반 알람 노티 → 돌 깨기 화면으로
            Task { @MainActor in
                AppRouter.shared.navigate(.breakingStone)
            }
        }
        completionHandler()
    }
}
//MARK: -- 노티 전체 삭제
extension NotificationService {
    static func cancelAllNotifications() {
        let c = UNUserNotificationCenter.current()
        c.removeAllPendingNotificationRequests()
        c.removeAllDeliveredNotifications()
    }
}
