//
//  AlarmEvaluationTests.swift
//  T8-NoFrankTests
//
//  알람 판정 순수 함수(evaluateAlarm) 단위 테스트.
//  실기기 빌드 + 실시간 1분 대기 없이, 가짜 시각을 주입해 즉시 검증한다.
//

import Testing
import Foundation
@testable import T8_NoFrank

@Suite("알람 판정 로직 (evaluateAlarm)")
struct AlarmEvaluationTests {

    /// 요일 결정성을 위해 타임존 고정 캘린더 사용
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    @Test("알람 시각이 지났고 선택 요일이면 → ring")
    func ringsWhenTimeReachedOnSelectedWeekday() {
        let alarm = date(2026, 5, 18, 7, 0)
        let now = alarm
        let weekday = calendar.component(.weekday, from: now)

        let result = BackgroundAudioPlayer.evaluateAlarm(
            now: now,
            alarmTime: alarm,
            isAlarmMode: false,
            selectedWeekdays: [weekday],
            calendar: calendar
        )
        #expect(result == .ring)
    }

    @Test("알람 시각 1초 전이면 → wait")
    func waitsBeforeAlarmTime() {
        let alarm = date(2026, 5, 18, 7, 0)
        let now = alarm.addingTimeInterval(-1)
        let weekday = calendar.component(.weekday, from: now)

        let result = BackgroundAudioPlayer.evaluateAlarm(
            now: now,
            alarmTime: alarm,
            isAlarmMode: false,
            selectedWeekdays: [weekday],
            calendar: calendar
        )
        #expect(result == .wait)
    }

    @Test("이미 알람 모드면 시각이 지나도 → wait (재발동 방지)")
    func waitsWhenAlreadyInAlarmMode() {
        let alarm = date(2026, 5, 18, 7, 0)
        let weekday = calendar.component(.weekday, from: alarm)

        let result = BackgroundAudioPlayer.evaluateAlarm(
            now: alarm,
            alarmTime: alarm,
            isAlarmMode: true,
            selectedWeekdays: [weekday],
            calendar: calendar
        )
        #expect(result == .wait)
    }

    @Test("시각은 지났지만 미선택 요일이면 → rescheduleToNextWeekday")
    func reschedulesOnUnselectedWeekday() {
        let alarm = date(2026, 5, 18, 7, 0)
        let now = alarm
        let weekday = calendar.component(.weekday, from: now)
        let everyWeekdayExceptToday = Set(1...7).subtracting([weekday])

        let result = BackgroundAudioPlayer.evaluateAlarm(
            now: now,
            alarmTime: alarm,
            isAlarmMode: false,
            selectedWeekdays: everyWeekdayExceptToday,
            calendar: calendar
        )
        #expect(result == .rescheduleToNextWeekday)
    }
}
