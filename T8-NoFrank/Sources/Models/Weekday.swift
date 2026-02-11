//
//  Weekday.swift
//  T8-NoFrank
//
//  Created by Codex on 2/10/26.
//

import Foundation

enum Weekday: Int, CaseIterable {
    case sun = 1
    case mon = 2
    case tue = 3
    case wed = 4
    case thu = 5
    case fri = 6
    case sat = 7

    static let ordered: [Weekday] = [.mon, .tue, .wed, .thu, .fri, .sat, .sun]
    static let weekdayCount = 7

    var labelKey: String {
        switch self {
        case .mon: return "weekday_mon"
        case .tue: return "weekday_tue"
        case .wed: return "weekday_wed"
        case .thu: return "weekday_thu"
        case .fri: return "weekday_fri"
        case .sat: return "weekday_sat"
        case .sun: return "weekday_sun"
        }
    }

    static func fromLegacyName(_ name: String) -> Weekday? {
        switch name {
        case "월", "Mon": return .mon
        case "화", "Tue": return .tue
        case "수", "Wed": return .wed
        case "목", "Thu": return .thu
        case "금", "Fri": return .fri
        case "토", "Sat": return .sat
        case "일", "Sun": return .sun
        default: return nil
        }
    }
}
