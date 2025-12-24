//
//  NotificationService.swift
//  T8-NoFrank
//
//  Created by 문창재 on 8/9/25.
//

import UserNotifications
import SwiftUI

struct NotificationService {
    
    // MARK: -- 권한 설정 함수
    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in

            }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    static let notiDelegate = NotificationDelegate()
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = Self.notiDelegate
        return true
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    // 앱이 포그라운드일 때도 배너/사운드 보이게
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .badge])
    }
}



// MARK: -- 노티 삭제 서비스
struct AlarmCancelService {
    
    // 모든 노티 제거
    static func cancelWeeklyBurstAll(weekdays: Set<Int>,
                                     hour: Int, minute: Int, second: Int,
                                     totalCount: Int,
                                     baseKey: String = "WEEKLY_BURST") {
       
        let ids: [String] = weekdays.flatMap { w in
            (0..<totalCount).map { i in
                "\(baseKey)_WD\(w)_\(hour)_\(minute)_\(second)_\(i)"
            }
        }

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)   // 아직 안 울린 것 제거
        center.removeDeliveredNotifications(withIdentifiers: ids)        // 알림 센터에 남은 것도 제거
    }
    
    
    //오늘 날짜의 노티 지우기
    static func cancelTodayBurst(hour: Int, minute: Int, second: Int,
                                 totalCount: Int,
                                 baseKey: String = "WEEKLY_BURST") {
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
    static let nameToInt: [String:Int] = ["일":1,"월":2,"화":3,"수":4,"목":5,"금":6,"토":7]
    static let intToName: [Int:String] = [1:"일",2:"월",3:"화",4:"수",5:"목",6:"금",7:"토"]

    static func toInts(from names: [String]) -> Set<Int> {
        Set(names.compactMap { nameToInt[$0] })
    }
    static func toNames(from ints: Set<Int>) -> [String] {
        ints.compactMap { intToName[$0] }.sorted { (nameToInt[$0] ?? 0) < (nameToInt[$1] ?? 0) }
    }
}

