//
//  BlowAwayStoneView.swift
//  T8-NoFrank
//
//  Created by JiJooMaeng on 8/8/25.
//

import SwiftUI

struct BlowAwayStoneView: View {
    /// 현재 알람이 울린 요일 (돌이 깨지는 요일)
    private let dayName: String = NextAlarmDayHelper.todayDayName
    /// 다음에 깨질 돌의 요일
    private let nextDayName: String = {
        let ud = UserDefaults(suiteName: AppConstants.appGroupID)!
        let hour = ud.object(forKey: "alarmHour") as? Int ?? 7
        let minute = ud.object(forKey: "alarmMinute") as? Int ?? 0
        let selectedNames = ud.stringArray(forKey: "alarmSelectedDays") ?? ["월", "화", "수", "목", "금"]
        return NextAlarmDayHelper.nextAlarmDayName(
            hour: hour, minute: minute, selectedDayNames: selectedNames
        )
    }()
    @State private var blowDetector = BlowDetector()
    @State private var autoNavigateTask: Task<Void, Never>?
    @State private var blowAwayTask: Task<Void, Never>?

    @State private var triggerActivated = false
    @State private var dustOffset: CGFloat = 0
    @State private var newStoneOffset: CGFloat = 400
    @State private var newStoneOpacity: Double = 0
    @State private var a2Offset: CGFloat = 0
    @State private var b2Offset: CGFloat = 0

    var body: some View {
        ZStack {
            Image("Home_Background")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .frame(width: screenWidth, height: screenHeight)

            Color.black
                .opacity(0.7)
                .ignoresSafeArea()
            
            VStack {
                if !triggerActivated {
                    Text(NSLocalizedString("broke_rock_title", comment: "돌이 깨졌어요"))
                        .font(.body01Bold)
                        .foregroundStyle(.white)
                        .padding(.top, 139)
                }
                Spacer()
            }

            ZStack {
                VStack {
                    Group {
                        if blowDetector.blowStage == 0 {
                            Image("\(dayName)/돌가루1")
                        } else if blowDetector.blowStage == 1 {
                            Image("\(dayName)/돌가루2")
                            Image("\(dayName)/떨어진 돌가루3")
                                .offset(
                                    x: a2Offset * 2 - 20,
                                    y: a2Offset * 2 - 100
                                )
                                .opacity(
                                    1.0 - min(1.0, Double(abs(a2Offset / 100)))
                                )
                        } else if blowDetector.blowStage == 2 {
                            Image("\(dayName)/돌가루3")
                            Image("\(dayName)/떨어진 돌가루2")
                                .offset(
                                    x: -b2Offset * 2 - 60,
                                    y: b2Offset * 2 - 100
                                )
                                .opacity(
                                    1.0 - min(1.0, Double(abs(b2Offset / 100)))
                                )
                        } else if blowDetector.blowStage == 3 {
                            Image("\(dayName)/돌가루3")
                                .offset(x: dustOffset)
                                .opacity(
                                    1.0
                                        - min(
                                            1.0,
                                            Double(abs(dustOffset / 300))
                                        )
                                )
                        }
                    }
                    Spacer()
                }
                .padding(.top, 426)
                VStack {
                    Image("\(nextDayName)/0단계")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 189, height: 230)
                        .rotationEffect(.degrees(newStoneOffset == 0 ? 0 : 720))
                        .offset(x: newStoneOffset)
                        .opacity(newStoneOpacity)
                    Spacer()
                }
                .padding(.top, 359)
            }
        }
        .onTapGesture {
            triggerBlowAwayAndNavigate()
        }
        .onChange(of: blowDetector.blowStage) { _, stage in
            switch stage {
            case 1:
                resetAutoNavigateTimer()
                withAnimation(.easeOut(duration: 1.5)) {
                    a2Offset = -200
                }
            case 2:
                resetAutoNavigateTimer()
                withAnimation(.easeOut(duration: 1.5)) {
                    b2Offset = -300
                }
            case 3:
                triggerBlowAwayAndNavigate()
            default:
                break
            }
        }
        .onDisappear {
            blowDetector.stop()
            autoNavigateTask?.cancel()
            blowAwayTask?.cancel()
        }
        .onAppear {
            triggerActivated = false
            dustOffset = 0
            newStoneOffset = 400
            newStoneOpacity = 0
            a2Offset = 0
            b2Offset = 0
            blowAwayTask = nil
            blowDetector.start()

            resetAutoNavigateTimer()
        }
    }

    private func resetAutoNavigateTimer() {
        autoNavigateTask?.cancel()
        autoNavigateTask = Task {
            try? await Task.sleep(for: .seconds(10))
            if !Task.isCancelled {
                await MainActor.run {
                    triggerBlowAwayAndNavigate()
                }
            }
        }
    }

    private func triggerBlowAwayAndNavigate() {
        guard blowAwayTask == nil else { return }

        autoNavigateTask?.cancel()
        blowDetector.stop()

        blowAwayTask = Task { @MainActor in
            withAnimation(.easeOut(duration: 2)) {
                dustOffset = -400
                newStoneOffset = 0
                newStoneOpacity = 1
                triggerActivated = true
            }

            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            AppRouter.shared.navigate(.home)
        }
    }
}

#Preview {
    BlowAwayStoneView()
}
