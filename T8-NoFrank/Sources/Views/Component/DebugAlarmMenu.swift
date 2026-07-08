//
//  DebugAlarmMenu.swift
//  T8-NoFrank
//
//  개발용 디버그 메뉴. `#if DEBUG` 가드로 Release/TestFlight 빌드에는 컴파일되지 않는다.
//  알람이 실제로 울릴 때까지 1분을 기다리지 않고, 버튼으로 즉시 울리고/끄기 위한 테스트 도구.
//

#if DEBUG
import SwiftUI

/// 우상단 툴바 위치에 뜨는 디버그 서랍(Menu).
/// 벌레 아이콘을 누르면 "알람 울리기 / 알람 종료하기" 두 액션이 펼쳐진다.
/// HomeView·BreakingStoneView 양쪽에 얹어, 어느 화면에서든 즉시 켜고 끌 수 있다.
struct DebugAlarmMenu: View {
    var body: some View {
        Menu {
            Button {
                // 실제 알람 발동 경로를 그대로 호출 → 즉시 울림 + 돌 깨기 화면 진입
                BackgroundAudioPlayer.shared.playAlarmSound()
                AppRouter.shared.navigate(.breakingStone)
            } label: {
                Label("알람 울리기", systemImage: "alarm.fill")
            }

            Button(role: .destructive) {
                // 돌 깨기 성공과 동일하게 알람 정지 + 무음 복귀 후 홈으로
                BackgroundAudioPlayer.shared.stopAlarmAndBackToSilent()
                AppRouter.shared.navigate(.home)
            } label: {
                Label("알람 종료하기", systemImage: "alarm.slash.fill")
            }
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

extension View {
    /// 어떤 화면이든 우상단 안전영역에 디버그 메뉴를 얹는다.
    /// 배포 빌드에서 흔적을 남기지 않도록 호출부도 `#if DEBUG`로 감싼다.
    ///
    /// GeometryReader로 실제 safe area top을 읽어 위치를 잡는다.
    /// - 부모가 `.ignoresSafeArea`면 safeAreaInsets.top이 노치 높이(~59)로 잡혀 그만큼 내려가고,
    /// - 부모가 safe area를 지키면 top이 ~0이라, 두 화면 모두 노치 바로 아래 툴바 위치에 정렬된다.
    func debugAlarmOverlay() -> some View {
        overlay(alignment: .topTrailing) {
            GeometryReader { proxy in
                DebugAlarmMenu()
                    .padding(.top, proxy.safeAreaInsets.top + 8)
                    .padding(.trailing, 16)
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
            }
        }
    }
}
#endif
