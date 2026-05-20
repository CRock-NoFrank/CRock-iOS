//
//  T8_NoFrankApp.swift
//  T8-NoFrank
//
//  Created by 이주현 on 8/7/25.
//

import SwiftUI

@main
struct T8_NoFrankApp: App {
    @StateObject private var router = AppRouter.shared
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(router)
                .ignoresSafeArea(.all)
        }
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .background:
                print("앱이 백그라운드로 전환됨")
            case .inactive:
                if router.currentScreen == .blowAwayStone {
                    router.navigate(.home)
                }
                print("앱이 비활성화됨")
            case .active:
                print("앱이 포그라운드 상태")
                if BackgroundAudioPlayer.shared.isAlarmMode {
                    // 앱이 살아있는 상태에서 포그라운드 복귀 → 돌 깨기 화면 유지
                    router.navigate(.breakingStone)
                } else if BackgroundAudioPlayer.isAlarmRingingPersisted() {
                    // 강제 종료 후 재실행 → 알람 상태 복원
                    let player = BackgroundAudioPlayer.shared
                    player.restoreOriginalVolumeFromPersistence()
                    player.playAlarmSound()
                    router.navigate(.breakingStone)
                } else if #available(iOS 26.0, *) {
                    // iOS 26+: AlarmKit fire 상태 감지 → BreakingStone 진입 + in-app loud audio 시작
                    // 락스크린 stop intent 거쳐 진입 / alerting 중 직접 진입 / 둘 다 커버.
                    let mgr = AlarmKitManager.shared
                    if mgr.hasAlertingAlarm || AlarmKitManager.wasAlarmRecentlyFired() || AlarmKitManager.needsRockBreak {
                        // 시스템 알람 사운드 정지 (in-app loud audio가 인계받음)
                        Task { await mgr.stopAlertingAlarms() }
                        let player = BackgroundAudioPlayer.shared
                        if !player.isAlarmMode {
                            player.playAlarmSound()
                        }
                        // 락스크린 stop 후 돌 안 깨고 앱 닫는 경우 대비 backup 60초 alarm 예약.
                        Task { await mgr.scheduleBackupAlarm() }
                        router.navigate(.breakingStone)
                    }
                }
                // 오디오 세션 인터럽트(전화, 유튜브 등) 이후 복원
                if BackgroundAudioPlayer.shared.isPlaying {
                    BackgroundAudioPlayer.shared.restoreAudioSession()
                }
            @unknown default:
                break
            }
        }
    }
}
