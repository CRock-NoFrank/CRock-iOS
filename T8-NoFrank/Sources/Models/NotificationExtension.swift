//
//  NotificationExtension.swift
//  T8-NoFrank
//
//  Created by 문창재 on 8/9/25.
//

import SwiftUI
import UserNotifications

extension NotificationService {
    //MARK: -- 선택한 요일에 요일당 8개의 노티 생성 (매주 반복)
    static func scheduleWeeklyBurst(
        weekdays: Set<Int>,
        hour: Int,
        minute: Int,
        second: Int,
        intervalSec: Int,
        count: Int,
        baseKey: String = "WEEKLY_BURST"
    ) {

        let center = UNUserNotificationCenter.current()
        let now = Date()
        let cal = Calendar.current
        let soundName: String? = "NotiSound28sec.caf"

        for w in weekdays {
            // 1) 다음 발생일 계산 (가장 가까운 w 요일의 지정 시:분:초)
            var match = DateComponents()
            match.weekday = w  // 1=일 ... 7=토
            match.hour = hour
            match.minute = minute
            match.second = second

            guard
                let base = cal.nextDate(
                    after: now,
                    matching: match,
                    matchingPolicy: .nextTime,
                    direction: .forward
                )
            else { continue }

            // 2) 30초 간격 × count개 생성
            for i in 0..<count {
                let fire = base.addingTimeInterval(
                    TimeInterval(intervalSec * i)
                )
                let comps = cal.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: fire
                )

                let content = UNMutableNotificationContent()
                content.title = "CRock"
                content.body = "돌 깨러가기" + String(repeating: "🪨", count: i + 1)
                content.userInfo = ["targetScreen": "TestView"]

                // 어떤 사운드 틀지 정하는 곳
                if let name = soundName {
                    content.sound = UNNotificationSound(named: .init(name))
                } else {
                    content.sound = .default
                }

                if #available(iOS 15.0, *) {
                    content.interruptionLevel = .timeSensitive
                }

                // 예측 가능한 식별자(요일·시·분·초·인덱스)
                let delta = intervalSec * i  // 0, 30, 60, ...
                let totalSec = second + delta  // 기준 초 + 오프셋
                let addMin = totalSec / 60
                let finalSec = totalSec % 60

                let totalMin = minute + addMin
                let addHour = totalMin / 60
                let finalMin = totalMin % 60

                let finalHour = (hour + addHour) % 24  // 안전하게 시 이월 처리

                var weeklyComps = DateComponents()
                weeklyComps.weekday = w  // 1=일 ... 7=토
                weeklyComps.hour = finalHour
                weeklyComps.minute = finalMin
                weeklyComps.second = finalSec

                let id =
                    "\(baseKey)_WD\(w)_\(finalHour)_\(finalMin)_\(finalSec)_\(i)"

                // 매주 반복
                let trig = UNCalendarNotificationTrigger(
                    dateMatching: weeklyComps,
                    repeats: true
                )
                let req = UNNotificationRequest(
                    identifier: id,
                    content: content,
                    trigger: trig
                )

                center.add(req)
                print("📅 매주 반복 노티 스케줄링: 요일\(w), 시간\(hour):\(minute), 인덱스\(i)")
            }
        }
    }

    //  매주 반복 노티 취소 함수도 수정
    static func cancelWeeklyBurst(
        weekdays: Set<Int>,
        hour: Int,
        minute: Int,
        second: Int,
        intervalSec: Int,
        count: Int = 8,
        baseKey: String = "WEEKLY_BURST"
    ) {
        var ids: [String] = []
        for w in weekdays {
            for i in 0..<count {
                let delta = intervalSec * i
                let totalSec = second + delta
                let addMin = totalSec / 60
                let finalSec = totalSec % 60

                let totalMin = minute + addMin
                let addHour = totalMin / 60
                let finalMin = totalMin % 60

                let finalHour = (hour + addHour) % 24

                let id =
                    "\(baseKey)_WD\(w)_\(finalHour)_\(finalMin)_\(finalSec)_\(i)"
                ids.append(id)
            }
        }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
        print("🗑️ 매주 반복 노티 취소: \(ids.count)개")
    }
}

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
