//
//  AlarmPlatform.swift
//  T8-NoFrank
//
//  버전마다 달라지는 "알람 깨우기 방식"의 역할 계약.
//  BackgroundAudioPlayer는 이 프로토콜에만 의존하고 실제 OS 버전은 모른다.
//

import Foundation

protocol AlarmPlatform {
    func clearStaleAlarms()
    func scheduleAlarm(hour: Int, minute: Int, weekdays: Set<Int>)

    func handleAlarmFired()

    func applyAlarmVolume(target: Float)
    func reinforceAlarmVolume(target: Float)
    func restoreAlarmVolume()
    func loadPersistedAlarmVolume()

    func stopAlerting()
    func cancelAll()

    var needsTerminationWarning: Bool { get }
}
