//
//  NotificationScheduling.swift
//  T8-NoFrank
//
//  UNUserNotificationCenter를 프로토콜 뒤로 추상화해 테스트 더블(Spy)로 교체 가능하게 한다.
//  운영 빌드는 기본값(SystemNotificationScheduler)이 실제 노티 센터를 그대로 호출하므로
//  런타임 동작 변화는 없다. 테스트에서만 SpyNotificationScheduler를 주입해
//  "언제 / 어떤 ID로 / 몇 개" 노티가 예약·제거됐는지 화이트박스로 검증한다.
//

import Foundation
import UserNotifications

/// 노티 예약/제거에 필요한 최소 인터페이스.
/// BackgroundAudioPlayer는 UNUserNotificationCenter를 직접 부르지 않고 이 프로토콜만 본다.
protocol NotificationScheduling {
    func add(_ request: UNNotificationRequest)
    func removePending(identifiers: [String])
    func removeDelivered(identifiers: [String])
}

/// 운영 구현체. 실제 UNUserNotificationCenter.current()로 위임한다.
struct SystemNotificationScheduler: NotificationScheduling {
    func add(_ request: UNNotificationRequest) {
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to schedule notification (\(request.identifier)): \(error)")
            }
        }
    }

    func removePending(identifiers: [String]) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeDelivered(identifiers: [String]) {
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}
