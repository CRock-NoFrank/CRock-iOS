//
//  AlarmPlatformFactory.swift
//  T8-NoFrank
//
//  버전 분기(if #available)를 앱 전체에서 이 한 곳으로 격리해 알람 플랫폼 구현체를 만든다.
//

import Foundation

enum AlarmPlatformFactory {
    static func make(scheduler: NotificationScheduling) -> AlarmPlatform {
        if #available(iOS 26.0, *) {
            return IOS26AlarmPlatform()
        } else {
            return IOS18AlarmPlatform(scheduler: scheduler)
        }
    }
}
