//
//  AlarmSettingView.swift
//  T8-NoFrank
//
//  Created by 나현흠 on 8/8/25.
//

import SwiftUI

struct AlarmSettingView: View {

    struct DayItem: Identifiable {
        let name: String
        var isSelected: Bool
        var id: String { name }
    }
    let isAlarmEnabled: Bool
    @Binding var time: Date
    @Binding var days: [DayItem]
    @Binding var volume: Double
    @Environment(\.dismiss) var dismiss
    
    private var hasSelectedDays: Bool {
        days.contains { $0.isSelected }
    }

    var body: some View {
        VStack {
            ZStack(alignment: .top) {
                Color(hex: "151515").edgesIgnoringSafeArea(.all)
                VStack {
                    DatePicker(
                        "",
                        selection: $time,
                        displayedComponents: [.hourAndMinute]
                    )
                    .padding(.horizontal, 0)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .environment(
                        \.locale,
                        Locale(
                            identifier: Locale.preferredLanguages.first ?? "ko"
                        )
                    )
                    .colorScheme(.dark)

                    VStack {
                        Text("요일")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(Color.white)
                            .font(.custom("Pretendard", size: 19))
                            .padding(.leading, 30)
                            .padding(.bottom, 17)
                        HStack(spacing: 9) {
                            ForEach($days, id: \.name) { $day in
                                WeekdayToggleButton(
                                    title: day.name,
                                    isSelected: $day.isSelected
                                )
                            }
                        }
                    }
                    .padding(.bottom, 30)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("볼륨")
                                .foregroundStyle(Color.white)
                                .font(.custom("Pretendard", size: 19))
                            Spacer()
                            Text("\(Int(volume * 100))%")
                                .foregroundStyle(Color.gray)
                                .font(.custom("Pretendard", size: 16))
                        }
                        .padding(.horizontal, 30)

                        Slider(value: $volume, in: 0.0...1.0)
                            .accentColor(Color(hex: "#BE5F1B"))
                            .padding(.horizontal, 30)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(
                    action: {
                        dismiss()
                    },
                    label: {
                        Text("취소")
                            .foregroundStyle(Color(hex: "#BE5F1B"))
                    }
                )
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(
                    action: {
                        saveAlarmSettings()
                        dismiss()
                    },
                    label: {
                        Text("저장")
                            .foregroundStyle(
                                hasSelectedDays 
                                ? Color(hex: "#BE5F1B") 
                                : Color.gray
                            )
                    }
                )
                .disabled(!hasSelectedDays)
            }
        }
    }

    // 🔥 알람 설정 저장
    private func saveAlarmSettings() {
        let comps = Calendar.current.dateComponents(
            [.hour, .minute],
            from: time
        )
        let hour = comps.hour ?? 0
        let minute = comps.minute ?? 0

        // 선택된 요일을 Set<Int>로 변환
        let weekdays: Set<Int> = Set(
            days.enumerated().compactMap { index, day in
                day.isSelected ? index + 1 : nil
            }
        )

        // 볼륨 저장
        UserDefaults(suiteName: AppConstants.appGroupID)!.set(
            volume,
            forKey: "alarmVolume"
        )

        if isAlarmEnabled {
            // 백그라운드 오디오 재시작
            BackgroundAudioPlayer.shared.stopAll()
            BackgroundAudioPlayer.shared.startSilentSound(
                hour: hour,
                minute: minute,
                weekdays: weekdays
            )
            print("AlarmSettingView에서 알람 설정 완료")
            print("🔔 요일: \(weekdays), 시간: \(hour):\(minute), 볼륨: \(Int(volume * 100))%")
        } else {
            print("알람이 비활성화되어 있습니다")
        }
    }
}

#Preview {
    HomeView()
}
