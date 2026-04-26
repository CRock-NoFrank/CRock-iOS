//
//  NotificationService.swift
//  T8-NoFrank
//
//  Created by 문창재 on 8/9/25.
//

import SwiftUI
import UserNotifications
import AVFoundation

struct NotificationService {
    // MARK: -- 권한 설정 함수
    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) {
                granted,
                error in

            }
    }
    
    static func requestMicrophonePermission() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if granted {
                print("마이크 권한이 허용되었습니다.")
            } else {
                print("마이크 권한이 거부되었습니다.")
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    static let notiDelegate = NotificationDelegate()
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication
            .LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = Self.notiDelegate
        return true
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    // 앱이 포그라운드일 때도 배너/사운드 보이게
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let id = notification.request.identifier
        // 앱이 살아있는 상태에서는 종료 경고/burst 알림을 표시하지 않음
        if id == "appTerminationWarning" || id.hasPrefix("ALARM_BURST_") {
            completionHandler([])
            return
        }
        completionHandler([.banner, .list, .badge])
    }
}

// MARK: -- 노티 삭제 서비스
extension NotificationService {

    // 모든 노티 제거
    static func cancelWeeklyBurstAll(
        weekdays: Set<Int>,
        hour: Int,
        minute: Int,
        second: Int,
        totalCount: Int,
        baseKey: String = "WEEKLY_BURST"
    ) {

        let ids: [String] = weekdays.flatMap { w in
            (0..<totalCount).map { i in
                "\(baseKey)_WD\(w)_\(hour)_\(minute)_\(second)_\(i)"
            }
        }

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)  // 아직 안 울린 것 제거
        center.removeDeliveredNotifications(withIdentifiers: ids)  // 알림 센터에 남은 것도 제거
    }

    //오늘 날짜의 노티 지우기
    static func cancelTodayBurst(
        hour: Int,
        minute: Int,
        second: Int,
        totalCount: Int,
        baseKey: String = "WEEKLY_BURST"
    ) {
        let todayWeekday = Calendar.current.component(.weekday, from: Date())
        print(todayWeekday)

        let ids: [String] = (0..<totalCount).map { i in
            "\(baseKey)_WD\(todayWeekday)_\(hour)_\(minute)_\(second)_\(i)"
        }
        print(ids)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)

        print("오늘거 지워짐")
    }
}

// 공용 매핑 유틸
enum WeekdayMap {
    static let nameToInt: [String: Int] = [
        "일": 1, "월": 2, "화": 3, "수": 4, "목": 5, "금": 6, "토": 7,
        "Sun": 1, "Mon": 2, "Tue": 3, "Wed": 4, "Thu": 5, "Fri": 6, "Sat": 7,
    ]

    static func toInts(from names: [String]) -> Set<Int> {
        Set(names.compactMap { nameToInt[$0] })
    }
    static func toNames(from ints: Set<Int>) -> [String] {
        ints.compactMap { Weekday(rawValue: $0) }.sorted {
            $0.rawValue < $1.rawValue
        }.map { NSLocalizedString($0.labelKey, comment: "요일") }
    }
}
