//
//  BackgroundAudioPlayerNotificationTests.swift
//  T8-NoFrankTests
//
//  알람 설정·해제 시 어떤 노티가 언제·몇 개·어떤 ID로 예약/제거되는지
//  Spy로 화이트박스 검증한다. 실기기 1분 대기 없이 ms 단위로 끝난다.
//
//  검증 대상:
//   1) startSilentSound          — 알람 대기 진입 시 이전 종료 경고 노티 정리
//   2) scheduleTerminationWarning — Dead Man's Switch 1개 등록
//   3) scheduleAlarmBurst         — 강제 종료 대비 60개 burst, 30초 간격, ID 패턴
//   4) cancelAlarmBurst           — 60개 pending + delivered 모두 제거
//   5) 회귀: burst + termination ≤ iOS 펜딩 64개 한도
//

import Testing
import Foundation
import UserNotifications
@testable import T8_NoFrank

@Suite("BackgroundAudioPlayer 노티 스케줄링 (Spy 기반 화이트박스)")
struct BackgroundAudioPlayerNotificationTests {

    /// 테스트 SUT 생성 헬퍼. 오디오 세션 셋업은 건너뛴다(부작용 차단).
    private func makeSUT() -> (BackgroundAudioPlayer, SpyNotificationScheduler) {
        let spy = SpyNotificationScheduler()
        let sut = BackgroundAudioPlayer(scheduler: spy, setupAudio: false)
        return (sut, spy)
    }

    // MARK: - 알람 "전" — 대기 모드 진입

    @Test("startSilentSound 호출 → 이전 종료 경고 노티 정리됨")
    func startSilentSound_clearsPreviousTerminationWarning() {
        let (sut, spy) = makeSUT()

        sut.startSilentSound(hour: 7, minute: 0, weekdays: [2, 3, 4, 5, 6])

        #expect(spy.removedPendingIDs.contains("appTerminationWarning"))
    }

    // MARK: - 종료 경고 노티 (Dead Man's Switch)

    @Test("scheduleTerminationWarning → 이전 경고 제거 후 1개만 새로 등록")
    func scheduleTerminationWarning_replacesPreviousWithOne() {
        let (sut, spy) = makeSUT()

        sut.scheduleTerminationWarning()

        // 이전 경고 제거 호출 발생
        #expect(spy.removedPendingIDs == ["appTerminationWarning"])
        // 정확히 1개 등록, ID 일치
        #expect(spy.addedIdentifiers == ["appTerminationWarning"])
        // 3초 트리거인지 확인
        let req = spy.addedRequests.first
        #expect(SpyNotificationScheduler.timeInterval(of: req!) == 3)
    }

    // MARK: - 알람 "중" — Burst 60개 예약

    @Test("scheduleAlarmBurst → ALARM_BURST_0~59 정확히 60개 등록")
    func scheduleAlarmBurst_schedulesExactly60() {
        let (sut, spy) = makeSUT()

        sut.scheduleAlarmBurst()

        let bursts = spy.addedRequests(withPrefix: "ALARM_BURST_")
        #expect(bursts.count == 60)

        // ID가 0..59까지 빠짐없이 존재
        let burstIDs = Set(bursts.map(\.identifier))
        let expectedIDs = Set((0..<60).map { "ALARM_BURST_\($0)" })
        #expect(burstIDs == expectedIDs)
    }

    @Test("scheduleAlarmBurst → 30초 간격(30, 60, 90 ... 1800)으로 증가")
    func scheduleAlarmBurst_intervalsAre30sStep() {
        let (sut, spy) = makeSUT()

        sut.scheduleAlarmBurst()

        // ID 순서대로 정렬해 간격 검증
        let bursts = spy.addedRequests(withPrefix: "ALARM_BURST_")
            .sorted { lhs, rhs in
                let li = Int(lhs.identifier.replacingOccurrences(of: "ALARM_BURST_", with: "")) ?? 0
                let ri = Int(rhs.identifier.replacingOccurrences(of: "ALARM_BURST_", with: "")) ?? 0
                return li < ri
            }

        let intervals = bursts.compactMap { SpyNotificationScheduler.timeInterval(of: $0) }
        #expect(intervals.first == 30)
        #expect(intervals.last == 1800)        // 30 * 60
        #expect(intervals.count == 60)

        // 연속 간격 모두 30초인지
        let allStep30 = zip(intervals, intervals.dropFirst()).allSatisfy { $1 - $0 == 30 }
        #expect(allStep30)
    }

    @Test("scheduleAlarmBurst → 등록 전 기존 burst 취소 호출됨 (cancelAlarmBurst 내부 호출)")
    func scheduleAlarmBurst_cancelsExistingBurstFirst() {
        let (sut, spy) = makeSUT()

        sut.scheduleAlarmBurst()

        // 내부에서 cancelAlarmBurst가 먼저 불려 60개 ID가 removePending/Delivered에 들어가야 함
        let expectedIDs = (0..<60).map { "ALARM_BURST_\($0)" }
        for id in expectedIDs {
            #expect(spy.removedPendingIDs.contains(id))
            #expect(spy.removedDeliveredIDs.contains(id))
        }
    }

    // MARK: - 알람 "후" — 정리

    @Test("cancelAlarmBurst → 60개 ID에 대해 pending + delivered 모두 제거")
    func cancelAlarmBurst_removesPendingAndDelivered() {
        let (sut, spy) = makeSUT()

        sut.cancelAlarmBurst()

        let expectedIDs = (0..<60).map { "ALARM_BURST_\($0)" }
        #expect(spy.removedPendingIDs == expectedIDs)
        #expect(spy.removedDeliveredIDs == expectedIDs)
    }

    // MARK: - 회귀: iOS 펜딩 64개 한도

    @Test("burst 60개 + 종료 경고 1개 = 61 ≤ iOS 한도 64")
    func totalPendingStaysUnder64Limit() {
        let (sut, spy) = makeSUT()

        sut.scheduleAlarmBurst()
        sut.scheduleTerminationWarning()

        // 같은 시점에 동시 등록될 수 있는 노티 총 개수
        let totalAdded = spy.addedRequests.count
        #expect(totalAdded <= 64, "iOS 펜딩 노티 한도(64개)를 초과하면 안 됨. 현재 \(totalAdded)개")
    }
}
