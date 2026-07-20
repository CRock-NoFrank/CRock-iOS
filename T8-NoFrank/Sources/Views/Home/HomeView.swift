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
    @State private var isModal: Bool = false
    @State private var alarmTime: Date = {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 9
        comps.minute = 41
        return Calendar.current.date(from: comps) ?? Date()
    }()
    @State private var alarmVolume: Double = 1.0
    @State private var alarmDays: [AlarmSettingView.DayItem] =
        Weekday.ordered.map { .init(weekday: $0, isSelected: false) }

    private var nextAlarmWeekday: Weekday? {
        let selectedWeekdays = Set(
            alarmDays.compactMap { $0.isSelected ? $0.weekday.rawValue : nil }
        )
        guard !selectedWeekdays.isEmpty else { return nil }

        let calendar = Calendar.current
        let now = Date()
        let comps = calendar.dateComponents([.hour, .minute], from: alarmTime)
        let alarmHour = comps.hour ?? 0
        let alarmMinute = comps.minute ?? 0

        for dayOffset in 0..<7 {
            let checkDate = calendar.date(byAdding: .day, value: dayOffset, to: now)!
            let weekday = calendar.component(.weekday, from: checkDate)

            if selectedWeekdays.contains(weekday) {
                var candidate = calendar.dateComponents([.year, .month, .day], from: checkDate)
                candidate.hour = alarmHour
                candidate.minute = alarmMinute
                candidate.second = 0

                if let candidateDate = calendar.date(from: candidate),
                   candidateDate > now {
                    return Weekday(rawValue: weekday)
                }
            }
        }
        return nil
    }

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
                MovingRockSpriteView(isBreakable: false, weekday: nextAlarmWeekday)
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
                    selectedWeekdays: Set(
                        alarmDays.filter { $0.isSelected }.map { $0.weekday.rawValue }
                    ),
                    date: alarmTime
                ) {
                    isModal.toggle()
                }
                .padding(.top, 160)
                .padding(.horizontal, 16)

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
                    initialTime: alarmTime,
                    initialDays: alarmDays,
                    initialVolume: alarmVolume,
                    onSave: { newTime, newDays, newVolume in
                        alarmTime = newTime
                        alarmDays = newDays
                        alarmVolume = newVolume
                        persistAlarm()
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                )
                .navigationTitle(NSLocalizedString("alarm_edit_title", comment: "알람 편집"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Color(hex: "151515"), for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
            }
            .presentationDetents([.fraction(0.7)])
            .presentationDragIndicator(.visible)
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
            let selectedWeekdays = alarmDays.compactMap { day in
                day.isSelected ? day.weekday.rawValue : nil
            }
            UserDefaults(suiteName: AppConstants.appGroupID)!.set(
                selectedWeekdays,
                forKey: "alarmSelectedWeekdays"
            )

            let weekdays: Set<Int> = Set(selectedWeekdays)

            if newValue == false {
                NotificationService.cancelAllNotifications()
                BackgroundAudioPlayer.shared.stopAll()
                print("알람 꺼짐")
            } else {
                BackgroundAudioPlayer.shared.startSilentSound(
                    hour: hour,
                    minute: minute,
                    weekdays: weekdays
                )
                print("알람 켜짐")
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
        let selectedWeekdays = alarmDays.compactMap { day in
            day.isSelected ? day.weekday.rawValue : nil
        }
        UserDefaults(suiteName: AppConstants.appGroupID)!.set(
            selectedWeekdays,
            forKey: "alarmSelectedWeekdays"
        )

        print(
            "[Alarm][persist] time=\(alarmTime) (hour=\(hour), minute=\(minute))"
        )
        print("[Alarm][persist] days=\(selectedWeekdays)")

        if isEnabled {
            let weekdays: Set<Int> = Set(
                alarmDays.compactMap { day in
                    day.isSelected ? day.weekday.rawValue : nil
                }
            )

            // 백그라운드 오디오 시작
            BackgroundAudioPlayer.shared.startSilentSound(
                hour: hour,
                minute: minute,
                weekdays: weekdays
            )
            print("알람 설정 완료")
        } else {
            BackgroundAudioPlayer.shared.stopAll()
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

        if let savedWeekdays = UserDefaults(suiteName: AppConstants.appGroupID)!
            .array(forKey: "alarmSelectedWeekdays") as? [Int]
        {
            let selected = Set(savedWeekdays)
            for i in alarmDays.indices {
                alarmDays[i].isSelected = selected.contains(alarmDays[i].weekday.rawValue)
            }
            print("[Alarm][load] days=\(savedWeekdays)")
        } else if let legacyNames = UserDefaults(suiteName: AppConstants.appGroupID)!
            .stringArray(forKey: "alarmSelectedDays")
        {
            let selected = Set(legacyNames.compactMap { Weekday.fromLegacyName($0)?.rawValue })
            for i in alarmDays.indices {
                alarmDays[i].isSelected = selected.contains(alarmDays[i].weekday.rawValue)
            }
            print("[Alarm][load] days=\(legacyNames)")
        } else {
            let defaultWeekdays: Set<Int> = [
                Weekday.mon.rawValue,
                Weekday.tue.rawValue,
                Weekday.wed.rawValue,
                Weekday.thu.rawValue,
                Weekday.fri.rawValue,
            ]
            for i in alarmDays.indices {
                alarmDays[i].isSelected = defaultWeekdays.contains(alarmDays[i].weekday.rawValue)
            }
            print("[Alarm][load] 기본 요일 설정: \(defaultWeekdays)")
        }

        // 볼륨 로드
        if let savedVolume = UserDefaults(suiteName: AppConstants.appGroupID)!
            .object(forKey: "alarmVolume") as? Double {
            alarmVolume = savedVolume
            print("[Alarm][load] volume=\(Int(savedVolume * 100))%")
        }

        // 앱 시작 시 백그라운드 오디오 복원
        // 알람이 울리는 중이면 silent sound 재시작하지 않음 (T8_NoFrankApp에서 breakingStone으로 이동)
        if isEnabled && !BackgroundAudioPlayer.isAlarmRingingPersisted() {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: alarmTime)
            let hour = comps.hour ?? 0
            let minute = comps.minute ?? 0

            let weekdays: Set<Int> = Set(alarmDays.compactMap { day in
                day.isSelected ? day.weekday.rawValue : nil
            })

            BackgroundAudioPlayer.shared.startSilentSound(
                hour: hour,
                minute: minute,
                weekdays: weekdays
            )
            print("앱 시작 시 백그라운드 오디오 복원 완료")
        }
    }
}

#Preview {
    HomeView()
}

struct AlarmCard: View {
    @Binding var isOn: Bool
    var timeText: String
    var selectedWeekdays: Set<Int>
    var date: Date
    var onTap: () -> Void

    private let days: [Weekday] = Weekday.ordered

    var amPm: String {
        let hour = Calendar.current.component(.hour, from: date)
        return hour < 12
            ? NSLocalizedString("alarm_am", comment: "오전")
            : NSLocalizedString("alarm_pm", comment: "오후")
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 4) {
                    ForEach(days.indices, id: \.self) { idx in
                        let weekday = days[idx]
                        Text(NSLocalizedString(weekday.labelKey, comment: "요일"))
                            .font(
                                selectedWeekdays.contains(weekday.rawValue)
                                    ? .caption1SemiBold : .caption1Medium
                            )
                            .foregroundStyle(
                                isOn
                                    ? (selectedWeekdays.contains(weekday.rawValue)
                                        ? .orange1 : .gray2)
                                    : (selectedWeekdays.contains(weekday.rawValue)
                                        ? .gray1 : .gray2)
                            )
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 13) {
                    Text(amPm)
                        .font(
                            .custom(Pretendard.regular.rawValue, size: 20)
                        )
                        .foregroundStyle(
                            isOn ? .white : .gray1
                        )

                    Text(timeText.isEmpty ? "07:00" : timeText)
                        .font(.custom(Pretendard.semiBold.rawValue, size: 30))
                        .foregroundStyle(
                            isOn ? .white : .gray1
                        )
                }
            }

            Spacer(minLength: 16)

            CustomToggle(isOn: $isOn)
        }
        .padding(24)
        .background {
            if #available(iOS 26.0, *) {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color(hex: "#070604").opacity(0.5))
                    .glassEffect(
                        .clear,
                        in: RoundedRectangle(
                            cornerRadius: 30,
                            style: .continuous
                        )
                    )
            } else {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(.black160)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 109)
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .onTapGesture { onTap() }
    }
}
