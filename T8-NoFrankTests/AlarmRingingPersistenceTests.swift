//
//  AlarmRingingPersistenceTests.swift
//  T8-NoFrankTests
//
//  강제 종료 후 재실행 시 "알람을 복원해야 하는가" 판정(isAlarmRingingValid) 단위 테스트.
//  30분 영속화 만료창 경계가 핵심 — 여기서 off-by-one이 나면 알람이 죽거나(복원 실패)
//  엉뚱하게 되살아난다. 시계/UserDefaults 없이 순수 함수에 값을 주입해 즉시 검증한다.
//

import Testing
import Foundation
@testable import T8_NoFrank

@Suite("알람 복원 판정 로직 (isAlarmRingingValid)")
struct AlarmRingingPersistenceTests {

    /// 30분(1800초) 영속화 만료창. BackgroundAudioPlayer.alarmRingingMaxDurationSec(private)와 동일해야 함.
    private let maxDuration: TimeInterval = 1800

    /// 결정성을 위한 임의 고정 기준 시각(epoch 초)
    private let now: Double = 10_000

    @Test("울리는 중이 아니면 → false (복원 안 함)")
    func notRingingReturnsFalse() {
        let result = BackgroundAudioPlayer.isAlarmRingingValid(
            isRinging: false,
            timestamp: now,                 // 시각은 유효해도
            now: now,
            maxDurationSec: maxDuration
        )
        #expect(result == false)
    }

    @Test("기록 타임스탬프가 없으면(0) → false")
    func zeroTimestampReturnsFalse() {
        let result = BackgroundAudioPlayer.isAlarmRingingValid(
            isRinging: true,
            timestamp: 0,
            now: now,
            maxDurationSec: maxDuration
        )
        #expect(result == false)
    }

    @Test("경과 1799초(창 안) → true (복원)")
    func justInsideWindowReturnsTrue() {
        let result = BackgroundAudioPlayer.isAlarmRingingValid(
            isRinging: true,
            timestamp: now - 1799,
            now: now,
            maxDurationSec: maxDuration
        )
        #expect(result == true)
    }

    @Test("경과 1801초(창 밖) → false (만료)")
    func justOutsideWindowReturnsFalse() {
        let result = BackgroundAudioPlayer.isAlarmRingingValid(
            isRinging: true,
            timestamp: now - 1801,
            now: now,
            maxDurationSec: maxDuration
        )
        #expect(result == false)
    }

    @Test("경과 정확히 1800초(경계) → false (< 비교라 미포함)")
    func exactlyAtBoundaryReturnsFalse() {
        let result = BackgroundAudioPlayer.isAlarmRingingValid(
            isRinging: true,
            timestamp: now - 1800,
            now: now,
            maxDurationSec: maxDuration
        )
        #expect(result == false)
    }
}
