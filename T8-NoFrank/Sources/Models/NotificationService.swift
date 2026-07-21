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
    
    static func requestMicrophonePermission(completion: ((Bool) -> Void)? = nil) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if granted {
                print("마이크 권한이 허용되었습니다.")
            } else {
                print("마이크 권한이 거부되었습니다.")
            }
            DispatchQueue.main.async {
                completion?(granted)
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
