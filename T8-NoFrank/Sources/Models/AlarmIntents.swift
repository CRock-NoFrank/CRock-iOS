//
//  AlarmIntents.swift
//  T8-NoFrank
//
//  AlarmKit stop 버튼용 LiveActivityIntent.
//  유저가 락스크린 stop 탭 → 인텐트 실행 → 앱 강제 오픈 + backup alarm 예약.
//

import Foundation

#if canImport(AlarmKit)
import AppIntents
import AlarmKit

@available(iOS 26.0, *)
struct BreakRockIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "돌 깨러 가기"
    static var description: IntentDescription = IntentDescription("CRock 알람을 끄고 돌 깨기 화면으로 이동합니다.")

    /// 인텐트 실행 시 앱을 강제로 포그라운드로 가져옴.
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {}

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // AlarmKit 알람은 stop 버튼 자동으로 정지되지만 명시적으로도 호출해 상태 동기화.
        if let uuid = UUID(uuidString: alarmID) {
            try? AlarmManager.shared.stop(id: uuid)
        }

        // 알람 fire 표시 (앱이 포그라운드 진입 시 BreakingStone으로 라우팅)
        AlarmKitManager.markAlarmFired()

        // 60초 후 backup alarm 예약 — 유저가 돌 안 깨면 다시 울림.
        await AlarmKitManager.shared.scheduleBackupAlarm()

        return .result()
    }
}
#endif
