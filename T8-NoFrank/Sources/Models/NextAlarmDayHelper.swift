//
//  NextAlarmDayHelper.swift
//  T8-NoFrank
//
//  다음 알람이 울릴 요일을 계산하는 헬퍼
//

import Foundation

enum NextAlarmDayHelper {
    /// Calendar.weekday (1=일, 2=월, 3=화, 4=수, 5=목, 6=금, 7=토) → 한국어 요일명
    private static let weekdayToKorean: [Int: String] = [
        1: "일", 2: "월", 3: "화", 4: "수",
        5: "목", 6: "금", 7: "토"
    ]

    /// 오늘의 요일을 한국어 이름으로 반환
    static var todayDayName: String {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return weekdayToKorean[weekday] ?? "월"
    }

    /// 다음 알람이 울릴 요일의 한국어 이름을 반환
    /// - Parameters:
    ///   - hour: 알람 시
    ///   - minute: 알람 분
    ///   - selectedDayNames: 선택된 요일 한국어 이름 배열 (예: ["월", "수", "금"])
    /// - Returns: 다음 알람 요일 한국어 이름 (예: "월")
    static func nextAlarmDayName(
        hour: Int,
        minute: Int,
        selectedDayNames: [String]
    ) -> String {
        guard !selectedDayNames.isEmpty else { return todayDayName }

        let calendar = Calendar.current
        let now = Date()

        // 한국어 요일명 → weekday 번호 변환
        let koreanToWeekday: [String: Int] = [
            "일": 1, "월": 2, "화": 3, "수": 4,
            "목": 5, "금": 6, "토": 7
        ]

        let selectedWeekdays: Set<Int> = Set(
            selectedDayNames.compactMap { koreanToWeekday[$0] }
        )

        for dayOffset in 0..<7 {
            guard let checkDate = calendar.date(byAdding: .day, value: dayOffset, to: now) else {
                continue
            }
            let weekday = calendar.component(.weekday, from: checkDate)

            if selectedWeekdays.contains(weekday) {
                var comps = calendar.dateComponents([.year, .month, .day], from: checkDate)
                comps.hour = hour
                comps.minute = minute
                comps.second = 0

                if let candidateDate = calendar.date(from: comps),
                   candidateDate > now {
                    return weekdayToKorean[weekday] ?? todayDayName
                }
            }
        }

        // 모든 후보가 과거일 경우 (오늘 포함 7일 뒤 같은 요일)
        // 선택된 요일 중 가장 빠른 다음 주 요일 반환
        return selectedDayNames.first ?? todayDayName
    }
}
