//
//  DebugAlarmMenu.swift
//  T8-NoFrank
//
//  개발용 디버그 메뉴. `#if DEBUG` 가드로 Release/TestFlight 빌드에는 컴파일되지 않는다.
//  알람이 실제로 울릴 때까지 1분을 기다리지 않고, 버튼으로 즉시 울리고/끄기 위한 테스트 도구.
//
//  사용 전제: 홈에서 알람 토글이 ON인 상태에서만 "알람 울리기"가 활성화된다.
//  실제 알람도 토글 ON(무음 루프 대기) 상태에서만 발동되므로, 그 전제를 그대로 따라
//  실제 흐름에서 생길 수 없는 상태(알람 OFF인데 울리는 중)를 디버그 버튼이 만들지 않게 한다.
//
//  검증 범위: 인앱 알람 사운드 → 돌 깨기 화면 → 흔들기 종료 → 볼륨 복원 → 홈 복귀.
//  iOS 26 AlarmKit 발동(잠금화면 알림/stop intent/backup 알람)은 이 버튼으로 재현되지 않는다.
//

#if DEBUG
import SwiftUI
import UIKit

/// 우상단 툴바 위치에 뜨는 디버그 서랍(Menu).
/// 벌레 아이콘을 누르면 "알람 울리기 / 알람 종료하기" 두 액션이 펼쳐진다.
/// HomeView·BreakingStoneView 양쪽에 얹어, 어느 화면에서든 즉시 켜고 끌 수 있다.
struct DebugAlarmMenu: View {
    /// isPlaying(토글 ON) / isAlarmMode(울리는 중) 변화에 따라 버튼 활성 상태를 갱신하기 위해 관찰.
    @ObservedObject private var player = BackgroundAudioPlayer.shared

    /// 알람 대기 중(토글 ON)이고 아직 울리지 않을 때만 울릴 수 있다.
    /// - 토글 OFF: 실제 흐름에 없는 상태라 차단 (무음 루프 잔존, burst 노티 미정리 방지)
    /// - 이미 울리는 중: playAlarmSound 재호출 시 "원래 볼륨"이 알람 볼륨으로 덮어써지는 것 방지
    private var canRing: Bool { player.isPlaying && !player.isAlarmMode }

    /// 울리는 중일 때만 종료할 수 있다.
    private var canStop: Bool { player.isAlarmMode }

    var body: some View {
        Menu {
            Button {
                guard canRing else { return }
                // 앱이 살아있을 때 알람 시각에 도달한 것과 동일한 경로 → 즉시 울림 + 돌 깨기 화면 진입
                BackgroundAudioPlayer.shared.playAlarmSound()
                AppRouter.shared.navigate(.breakingStone)
            } label: {
                Label("알람 울리기", systemImage: "alarm.fill")
            }
            .disabled(!canRing)

            Button(role: .destructive) {
                guard canStop else { return }
                // 돌 깨기 성공과 동일하게 알람 정지 + 무음 복귀 후 홈으로
                BackgroundAudioPlayer.shared.stopAlarmAndBackToSilent()
                AppRouter.shared.navigate(.home)
            } label: {
                Label("알람 종료하기", systemImage: "stop.circle.fill")
            }
            .disabled(!canStop)
        } label: {
            Image(systemName: "ladybug.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .padding(10)
                .background(Circle().fill(Color.black.opacity(0.5)))
        }
        .accessibilityIdentifier("debugAlarmMenu")
    }
}

/// 실제 윈도우의 상단 safe area inset(노치/다이내믹 아일랜드 높이).
///
/// SwiftUI의 `GeometryReader.safeAreaInsets`는 부모가 `.ignoresSafeArea`면 0으로 잡혀
/// 오버레이가 노치 위로 올라가버린다. 그래서 SwiftUI 계층이 아닌 UIKit 윈도우에서 직접 읽는다.
private var deviceTopSafeAreaInset: CGFloat {
    UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first { $0.isKeyWindow }?
        .safeAreaInsets.top ?? 0
}

extension View {
    /// 어떤 화면이든 우상단 안전영역 안쪽(노치 바로 아래 툴바 위치)에 디버그 메뉴를 얹는다.
    /// 배포 빌드에서 흔적을 남기지 않도록 호출부도 `#if DEBUG`로 감싼다.
    func debugAlarmOverlay() -> some View {
        overlay(alignment: .topTrailing) {
            DebugAlarmMenu()
                .padding(.top, deviceTopSafeAreaInset + 8)
                .padding(.trailing, 16)
        }
    }
}
#endif
