//
//  HomeView.swift
//  T8-NoFrank
//
//  Created by 나현흠 on 8/8/25.
//

import SwiftUI
import WidgetKit

enum AppConstants {
    static let appGroupID = "group.CRockWidget"  // TODO: replace with your real App Group ID
}

struct HomeView: View {
    @AppStorage(
        "isAlarmEnabled",
        store: UserDefaults(suiteName: AppConstants.appGroupID)!
    ) private var isEnabled: Bool = false
    @State private var isAnimating: Bool = false
    @State private var isModal: Bool = false
    @State private var Time: String = "00:00"
    @State private var alarmTime = Date()
    @State private var shouldNavigate: Bool = false
    @State private var targetScreen: String = ""
    @State private var alarmDays: [AlarmSettingView.DayItem] = [
        .init(name: "일", isSelected: false),
        .init(name: "월", isSelected: false),
        .init(name: "화", isSelected: false),
        .init(name: "수", isSelected: false),
        .init(name: "목", isSelected: false),
        .init(name: "금", isSelected: false),
        .init(name: "토", isSelected: false),
    ]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Image("Home_Background")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .frame(width: screenWidth, height: screenHeight)

            Color.black
                .opacity(0.7)
                .edgesIgnoringSafeArea(.all)

            if isEnabled {
                MovingRockSpriteView(isBreakable: false)
                Image("RotationGrass")
                    .resizable()
                    .scaledToFill()
                    .frame(width: screenWidth, height: screenHeight)
                    .onAppear {
                        WidgetCenter.shared.reloadAllTimelines()
                    }
            } else {
                Image("RockChain")
                    .resizable()
                    .scaledToFit()
                    .onAppear {
                        WidgetCenter.shared.reloadAllTimelines()
                    }
            }

            VStack {
                AlarmCard(
                    isOn: $isEnabled,
                    timeText: timeTextFormatted,
                    selectedDays: alarmDays.filter { $0.isSelected }.map {
                        $0.name
                    },
                    date: alarmTime
                ) {
                    isModal.toggle()
                }
                .padding(.top, 131)
                .padding(.horizontal, 31)

                Spacer()
            }
        }
        .frame(width: screenWidth, height: screenHeight)
        .ignoresSafeArea(.all)
        .onAppear {
            loadAlarm()
            NotificationService.requestAuthorization()
        }
        .sheet(isPresented: $isModal) {
            NavigationStack {
                AlarmSettingView(
                    isAlarmEnabled: isEnabled,
                    time: $alarmTime,
                    days: $alarmDays  // 🔥 추가
                )
                .navigationTitle("알람 편집")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Color(hex: "151515"), for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
            }
            .presentationDetents([.fraction(0.6)])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: isModal) { newValue in
            if newValue == false {
                persistAlarm()
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
        .onChange(of: isEnabled) { newValue in
            UserDefaults(suiteName: AppConstants.appGroupID)!.set(
                alarmTime,
                forKey: "alarmTime"
            )
            let comps = Calendar.current.dateComponents(
                [.hour, .minute],
                from: alarmTime
            )
            let hour = comps.hour ?? -1
            let minute = comps.minute ?? -1
            if comps.hour != nil && comps.minute != nil {
                UserDefaults(suiteName: AppConstants.appGroupID)!.set(
                    hour,
                    forKey: "alarmHour"
                )
                UserDefaults(suiteName: AppConstants.appGroupID)!.set(
                    minute,
                    forKey: "alarmMinute"
                )
            }
            let selectedNames = alarmDays.filter { $0.isSelected }.map {
                $0.name
            }
            UserDefaults(suiteName: AppConstants.appGroupID)!.set(
                selectedNames,
                forKey: "alarmSelectedDays"
            )

            let weekdays: Set<Int> = Set(
                alarmDays.enumerated().compactMap { index, day in
                    day.isSelected ? index + 1 : nil
                }
            )

            if newValue == false {
                NotificationService.cancelAllNotifications()
                print("모든 노티 삭제")
            } else {
                NotificationService.cancelAllNotifications()
                NotificationService.scheduleWeeklyBurst(
                    weekdays: weekdays,
                    hour: hour,
                    minute: minute,
                    second: 0,
                    intervalSec: 30,  // 30초 간격
                    count: 8  // 8개의 노티
                )
                print("노티 추가됨")
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private var timeTextFormatted: String {
        let comps = Calendar.current.dateComponents(
            [.hour, .minute],
            from: alarmTime
        )
        var hour = comps.hour ?? 0
        let minute = comps.minute ?? 0
        if hour == 0 {
            hour = 12
        } else if hour > 12 {
            hour -= 12
        }
        return String(format: "%02d:%02d", hour, minute)
    }
    private func checkNotificationNavigation() {
        if UserDefaults(suiteName: AppConstants.appGroupID)!.bool(
            forKey: "shouldNavigate"
        ) {
            shouldNavigate = true
            targetScreen =
                UserDefaults(suiteName: AppConstants.appGroupID)!.string(
                    forKey: "targetScreen"
                ) ?? ""

            // 신호 초기화
            UserDefaults(suiteName: AppConstants.appGroupID)!.set(
                false,
                forKey: "shouldNavigate"
            )
            UserDefaults(suiteName: AppConstants.appGroupID)!.removeObject(
                forKey: "targetScreen"
            )

            print("노티피케이션으로 \(targetScreen) 화면으로 이동")
        }
    }

    private func persistAlarm() {
        UserDefaults(suiteName: AppConstants.appGroupID)!.set(
            alarmTime,
            forKey: "alarmTime"
        )
        let comps = Calendar.current.dateComponents(
            [.hour, .minute],
            from: alarmTime
        )
        let hour = comps.hour ?? -1
        let minute = comps.minute ?? -1
        if comps.hour != nil && comps.minute != nil {
            UserDefaults(suiteName: AppConstants.appGroupID)!.set(
                hour,
                forKey: "alarmHour"
            )
            UserDefaults(suiteName: AppConstants.appGroupID)!.set(
                minute,
                forKey: "alarmMinute"
            )
        }
        let selectedNames = alarmDays.filter { $0.isSelected }.map { $0.name }
        UserDefaults(suiteName: AppConstants.appGroupID)!.set(
            selectedNames,
            forKey: "alarmSelectedDays"
        )

        print(
            "[Alarm][persist] time=\(alarmTime) (hour=\(hour), minute=\(minute))"
        )
        print("[Alarm][persist] days=\(selectedNames)")

        if isEnabled {
            let weekdays: Set<Int> = Set(
                alarmDays.enumerated().compactMap { index, day in
                    day.isSelected ? index + 1 : nil
                }
            )
            // 기존 매주 반복 노티 취소
            NotificationService.cancelAllNotifications()

            // 새로운 매주 반복 노티 스케줄링
            NotificationService.scheduleWeeklyBurst(
                weekdays: weekdays,
                hour: hour,
                minute: minute,
                second: 0,
                intervalSec: 30,
                count: 8
            )
            print("매주 반복 노티 재설정 완료")
        } else {
            // 알람이 비활성화되면 모든 매주 반복 노티 취소
            let allWeekdays: Set<Int> = [1, 2, 3, 4, 5, 6, 7]
            NotificationService.cancelAllNotifications()
        }
    }

    private func loadAlarm() {
        if let hour = UserDefaults(suiteName: AppConstants.appGroupID)!.object(
            forKey: "alarmHour"
        ) as? Int,
            let minute = UserDefaults(suiteName: AppConstants.appGroupID)!
                .object(forKey: "alarmMinute") as? Int
        {
            var comps = Calendar.current.dateComponents(
                [.year, .month, .day],
                from: Date()
            )
            comps.hour = hour
            comps.minute = minute
            if let rebuilt = Calendar.current.date(from: comps) {
                alarmTime = rebuilt
            }
        } else if let savedTime = UserDefaults(
            suiteName: AppConstants.appGroupID
        )!.object(forKey: "alarmTime") as? Date {
            alarmTime = savedTime
        }
        print("[Alarm][load] time=\(alarmTime)")

        if let names = UserDefaults(suiteName: AppConstants.appGroupID)!
            .stringArray(forKey: "alarmSelectedDays")
        {
            for i in alarmDays.indices {
                alarmDays[i].isSelected = names.contains(alarmDays[i].name)
            }
            print("[Alarm][load] days=\(names)")
        }

        // 앱 시작 시 매주 반복 노티 복원
        //        if isEnabled {
        //            let comps = Calendar.current.dateComponents([.hour, .minute], from: alarmTime)
        //            let hour = comps.hour ?? 0
        //            let minute = comps.minute ?? 0
        //
        //            let weekdays: Set<Int> = Set(alarmDays.enumerated().compactMap { index, day in
        //                day.isSelected ? index + 1 : nil
        //            })
        //
        //            NotificationService.scheduleWeeklyBurst(
        //                weekdays: weekdays,
        //                hour: hour,
        //                minute: minute,
        //                second: 0,
        //                intervalSec: 30,
        //                count: 8
        //            )
        //            print("앱 시작 시 매주 반복 노티 복원 완료")
        //        }
    }
}

#Preview {
    HomeView()
}

struct AlarmCard: View {
    @Binding var isOn: Bool
    var timeText: String
    var selectedDays: [String]
    var date: Date
    var onTap: () -> Void

    private let days: [String] = ["일", "월", "화", "수", "목", "금", "토"]

    var amPm: String {
        let hour = Calendar.current.component(.hour, from: date)
        return hour < 12 ? "오전" : "오후"
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.black.opacity(0.48))

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        ForEach(days.indices, id: \.self) { idx in
                            let label = days[idx]
                            Text(label)
                                .font(
                                    .custom(
                                        Pretendard.regular.rawValue,
                                        size: 17
                                    )
                                )
                                .fontWeight(
                                    selectedDays.contains(label)
                                        ? .semibold : .regular
                                )
                                .foregroundStyle(
                                    !selectedDays.contains(label)
                                        ? Color(hex: "#969698")
                                        : (isOn
                                            ? Color(hex: "#BE5F1B")
                                            : Color(hex: "#282828"))
                                )
                        }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(amPm)
                            .font(
                                .custom(Pretendard.regular.rawValue, size: 20)
                            )
                            .foregroundStyle(
                                isOn ? .white : Color(hex: "#969698")
                            )
                            .opacity(0.9)

                        Text(timeText.isEmpty ? "07:00" : timeText)
                            .font(.custom(Pretendard.bold.rawValue, size: 30))
                            .foregroundStyle(
                                isOn ? .white : Color(hex: "#969698")
                            )
                    }
                }

                Spacer(minLength: 16)

                CustomToggle(isOn: $isOn)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 109)
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .onTapGesture { onTap() }
    }
}
