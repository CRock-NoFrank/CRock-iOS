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

    // 🔥 알람 설정 저장 및 노티피케이션 스케줄링
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

        if isAlarmEnabled {
            // 기존 노티피케이션 취소
            NotificationService.cancelAllNotifications()

            // 새로운 노티피케이션 스케줄링
            NotificationService.scheduleWeeklyBurst(
                weekdays: weekdays,
                hour: hour,
                minute: minute,
                second: 0,
                intervalSec: 30,
                count: 8
            )
            print(" AlarmSettingView에서 노티피케이션 스케줄링 완료")
            print("🔔 요일: \(weekdays), 시간: \(hour):\(minute)")
        } else {
            print(" 알람이 비활성화되어 있어서 노티피케이션을 스케줄링하지 않습니다")
        }
    }
}

#Preview {
    HomeView()
}
