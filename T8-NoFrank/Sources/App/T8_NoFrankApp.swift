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
