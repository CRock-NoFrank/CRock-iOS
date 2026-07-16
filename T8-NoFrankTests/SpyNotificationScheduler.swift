//
//  SpyNotificationScheduler.swift
//  T8-NoFrankTests
//
//  NotificationScheduling의 테스트 더블(Spy).
//  실제 노티 센터는 건드리지 않고 "add / removePending / removeDelivered"
//  호출 기록만 저장한다. 테스트는 이 기록을 읽어 화이트박스로 검증한다.
//

import Foundation
import UserNotifications
@testable import T8_NoFrank

final class SpyNotificationScheduler: NotificationScheduling {

    // MARK: - 호출 기록 (호출 순서대로 누적)
    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var removedPendingIDs: [String] = []
    private(set) var removedDeliveredIDs: [String] = []

    // MARK: - NotificationScheduling
    func add(_ request: UNNotificationRequest) {
        addedRequests.append(request)
    }

    func removePending(identifiers: [String]) {
        removedPendingIDs.append(contentsOf: identifiers)
    }

    func removeDelivered(identifiers: [String]) {
        removedDeliveredIDs.append(contentsOf: identifiers)
    }

    // MARK: - 조회 헬퍼 (테스트 단언을 짧게 쓰기 위한 도우미)

    /// 예약된 요청들의 identifier 목록
    var addedIdentifiers: [String] {
        addedRequests.map(\.identifier)
    }

    /// identifier prefix로 필터링된 요청들
    func addedRequests(withPrefix prefix: String) -> [UNNotificationRequest] {
        addedRequests.filter { $0.identifier.hasPrefix(prefix) }
    }

    /// 특정 요청의 UNTimeIntervalNotificationTrigger 값 (아니면 nil) — 종료 경고 노티 검증용
    static func timeInterval(of request: UNNotificationRequest) -> TimeInterval? {
        (request.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval
    }

    /// 특정 요청의 UNCalendarNotificationTrigger second 컴포넌트 (아니면 nil) — burst 노티 검증용
    static func calendarSecond(of request: UNNotificationRequest) -> Int? {
        (request.trigger as? UNCalendarNotificationTrigger)?.dateComponents.second
    }

    /// 특정 요청의 UNCalendarNotificationTrigger repeats 여부 (아니면 nil)
    static func calendarRepeats(of request: UNNotificationRequest) -> Bool? {
        (request.trigger as? UNCalendarNotificationTrigger)?.repeats
    }
}
