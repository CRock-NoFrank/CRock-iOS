//
//  BackgroundAudioPlayerNotificationTests.swift
//  T8-NoFrankTests
//
//  알람 설정·해제 시 어떤 노티가 언제·몇 개·어떤 ID로 예약/제거되는지
//  Spy로 화이트박스 검증한다. 실기기 1분 대기 없이 ms 단위로 끝난다.
//
//  ⚠️ #112 이후 burst 설계: UNCalendarNotificationTrigger 기반.
//     매 분 0, 2, 4, ..., 58초에 발동되는 노티 30개를 repeats:true로 등록 → 시계 기반 무한 반복.
//     (기존 UNTimeInterval 60개×30초 설계는 폐기됨)
//
//  검증 대상:
//   1) startSilentSound          — 알람 대기 진입 시 이전 종료 경고 노티 정리
//   2) scheduleTerminationWarning — Dead Man's Switch 1개 등록 (3초 UNTimeInterval)
//   3) scheduleAlarmBurst         — burst 30개 / second 0,2,…,58 / repeats:true / ID 패턴
//   4) cancelAlarmBurst           — 30개 pending + delivered 모두 제거
//   5) 회귀: burst + termination ≤ iOS 펜딩 64개 한도
//

import Testing
import Foundation
import UserNotifications
@testable import T8_NoFrank

@Suite("BackgroundAudioPlayer 노티 스케줄링 (Spy 기반 화이트박스)")
struct BackgroundAudioPlayerNotificationTests {

    /// #112 burst 설계 상수 (BackgroundAudioPlayer 내부 private 상수와 동일해야 함)
    private let burstCount = 30
    private let burstIntervalSec = 2
    private let burstPrefix = "ALARM_BURST_"

    /// 테스트 SUT 생성 헬퍼. 오디오 세션 셋업은 건너뛴다(부작용 차단).
    private func makeSUT() -> (BackgroundAudioPlayer, SpyNotificationScheduler) {
        let spy = SpyNotificationScheduler()
        let sut = BackgroundAudioPlayer(scheduler: spy, setupAudio: false)
        return (sut, spy)
    }

    /// burst 요청들을 ID 인덱스(0,1,2…) 오름차순으로 정렬
    private func sortedBursts(_ spy: SpyNotificationScheduler) -> [UNNotificationRequest] {
        spy.addedRequests(withPrefix: burstPrefix)
            .sorted { lhs, rhs in
                let li = Int(lhs.identifier.replacingOccurrences(of: burstPrefix, with: "")) ?? 0
                let ri = Int(rhs.identifier.replacingOccurrences(of: burstPrefix, with: "")) ?? 0
                return li < ri
            }
    }

    // MARK: - 알람 "전" — 대기 모드 진입

    @Test("startSilentSound 호출 → 이전 종료 경고 노티 정리됨")
    func startSilentSound_clearsPreviousTerminationWarning() {
        let (sut, spy) = makeSUT()

        sut.startSilentSound(hour: 7, minute: 0, weekdays: [2, 3, 4, 5, 6])

        #expect(spy.removedPendingIDs.contains("appTerminationWarning"))
    }

    // MARK: - 종료 경고 노티 (Dead Man's Switch)

    @Test("scheduleTerminationWarning → 이전 경고 제거 후 1개만 새로 등록 (3초)")
    func scheduleTerminationWarning_replacesPreviousWithOne() {
        let (sut, spy) = makeSUT()

        sut.scheduleTerminationWarning()

        // 이전 경고 제거 호출 발생
        #expect(spy.removedPendingIDs == ["appTerminationWarning"])
        // 정확히 1개 등록, ID 일치
        #expect(spy.addedIdentifiers == ["appTerminationWarning"])
        // 3초 UNTimeInterval 트리거인지 확인
        let req = spy.addedRequests.first
        #expect(SpyNotificationScheduler.timeInterval(of: req!) == 3)
    }

    // MARK: - 알람 "중" — Burst 30개 예약 (UNCalendar)

    @Test("scheduleAlarmBurst → ALARM_BURST_0~29 정확히 30개 등록")
    func scheduleAlarmBurst_schedulesExactly30() {
        let (sut, spy) = makeSUT()

        sut.scheduleAlarmBurst()

        let bursts = spy.addedRequests(withPrefix: burstPrefix)
        #expect(bursts.count == burstCount)

        // ID가 0..29까지 빠짐없이 존재
        let burstIDs = Set(bursts.map(\.identifier))
        let expectedIDs = Set((0..<burstCount).map { "\(burstPrefix)\($0)" })
        #expect(burstIDs == expectedIDs)
    }

    @Test("scheduleAlarmBurst → second 0,2,4…58 + repeats:true (시계 기반 무한 반복)")
    func scheduleAlarmBurst_calendarSecondsAndRepeats() {
        let (sut, spy) = makeSUT()

        sut.scheduleAlarmBurst()

        let bursts = sortedBursts(spy)

        // 각 burst의 second 컴포넌트가 인덱스 × 2초 = 0,2,4,…,58 이어야 함
        let seconds = bursts.compactMap { SpyNotificationScheduler.calendarSecond(of: $0) }
        let expectedSeconds = (0..<burstCount).map { $0 * burstIntervalSec }
        #expect(seconds == expectedSeconds)
        #expect(seconds.first == 0)
        #expect(seconds.last == 58)              // 29 × 2

        // 전부 repeats:true (시계 기반 무한 반복) 여야 강제 종료 후에도 영원히 울림
        let allRepeat = bursts.allSatisfy { SpyNotificationScheduler.calendarRepeats(of: $0) == true }
        #expect(allRepeat)
    }

    @Test("scheduleAlarmBurst → 등록 전 기존 burst 30개 ID를 pending에서 제거 (중복 방지)")
    func scheduleAlarmBurst_removesExistingBurstFirst() {
        let (sut, spy) = makeSUT()

        sut.scheduleAlarmBurst()

        // #112: 등록 직전 scheduler.removePending(ids)로 좀비 burst 제거
        let expectedIDs = (0..<burstCount).map { "\(burstPrefix)\($0)" }
        for id in expectedIDs {
            #expect(spy.removedPendingIDs.contains(id))
        }
    }

    // MARK: - 알람 "후" — 정리

    @Test("cancelAlarmBurst → 30개 ID에 대해 pending + delivered 모두 제거")
    func cancelAlarmBurst_removesPendingAndDelivered() {
        let (sut, spy) = makeSUT()

        sut.cancelAlarmBurst()

        let expectedIDs = (0..<burstCount).map { "\(burstPrefix)\($0)" }
        #expect(spy.removedPendingIDs == expectedIDs)
        #expect(spy.removedDeliveredIDs == expectedIDs)
    }

    // MARK: - 회귀: iOS 펜딩 64개 한도

    @Test("burst 30개 + 종료 경고 1개 = 31 ≤ iOS 한도 64")
    func totalPendingStaysUnder64Limit() {
        let (sut, spy) = makeSUT()

        sut.scheduleAlarmBurst()
        sut.scheduleTerminationWarning()

        // 같은 시점에 동시 등록될 수 있는 노티 총 개수
        let totalAdded = spy.addedRequests.count
        #expect(totalAdded <= 64, "iOS 펜딩 노티 한도(64개)를 초과하면 안 됨. 현재 \(totalAdded)개")
    }
}
