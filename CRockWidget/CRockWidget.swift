//
//  CRockWidget.swift
//  CRockWidget
//
//  Created by 나현흠 on 8/9/25.
//

import WidgetKit
import SwiftUI

enum AppConstants {
    static let appGroupID = "group.CRockWidget" // MUST match the app target
}

private enum WidgetStore {
    static let defaults = UserDefaults(suiteName: AppConstants.appGroupID)

    static func load() -> (isEnabled: Bool, amPm: String, timeText: String) {
        let enabled = defaults?.bool(forKey: "isAlarmEnabled") ?? false
        let hour = defaults?.integer(forKey: "alarmHour")
        let minute = defaults?.integer(forKey: "alarmMinute")
        let hasHM = (defaults?.object(forKey: "alarmHour") != nil) && (defaults?.object(forKey: "alarmMinute") != nil)

        if enabled, hasHM, let h = hour, let m = minute {
            let ampm = h < 12
                ? NSLocalizedString("alarm_am", comment: "오전")
                : NSLocalizedString("alarm_pm", comment: "오후")
            var displayHour = h
            if displayHour == 0 {
                displayHour = 12
            } else if displayHour > 12 {
                displayHour -= 12
            }
            let timeText = String(format: "%02d:%02d", displayHour, m)
            return (true, ampm, timeText)
        } else {
            if hasHM, let h = hour, let m = minute {
                let ampm = h < 12
                    ? NSLocalizedString("alarm_am", comment: "오전")
                    : NSLocalizedString("alarm_pm", comment: "오후")
                var displayHour = h
                if displayHour == 0 {
                    displayHour = 12
                } else if displayHour > 12 {
                    displayHour -= 12
                }
                let timeText = String(format: "%02d:%02d", displayHour, m)
                return (enabled, ampm, timeText)
            } else {
                return (enabled, NSLocalizedString("alarm_am", comment: "오전"), "07:00")
            }
        }
    }
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        let loaded = WidgetStore.load()
        return SimpleEntry(date: Date(), configuration: ConfigurationAppIntent(), isEnabled: loaded.isEnabled, amPm: loaded.amPm, timeText: loaded.timeText)
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> SimpleEntry {
        let loaded = WidgetStore.load()
        return SimpleEntry(date: Date(), configuration: configuration, isEnabled: loaded.isEnabled, amPm: loaded.amPm, timeText: loaded.timeText)
    }
    
    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<SimpleEntry> {
        var entries: [SimpleEntry] = []

        let currentDate = Date()
        for secondOffset in stride(from: 0, through: 120, by: 3) {
            let entryDate = Calendar.current.date(byAdding: .second, value: secondOffset, to: currentDate)!
            let loaded = WidgetStore.load()
            let entry = SimpleEntry(date: entryDate, configuration: configuration, isEnabled: loaded.isEnabled, amPm: loaded.amPm, timeText: loaded.timeText)
            entries.append(entry)
        }

        return Timeline(entries: entries, policy: .atEnd)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationAppIntent
    let isEnabled: Bool
    let amPm: String
    let timeText: String
}

struct CRockWidgetEntryView : View {
    var entry: Provider.Entry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .opacity(0.3)
                VStack {
                    if entry.isEnabled {
                        VStack(spacing: 0) {
                            Text(entry.amPm)
                                .font(.system(size: 10))
                            Text(entry.timeText)
                                .font(.system(size: 10))
                                .padding(.bottom, 2)
                            Image("LockScreenWidget")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                        }
                    } else {
                        VStack(spacing: 0) {
                            Text(NSLocalizedString("widget_no_alarm", comment: "없음"))
                                .font(.system(size: 12))
                                .padding(.bottom, 2)
                            Image("LockScreenWidget")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .opacity(0.5)
                        }
                    }
                }
            }
        case .systemMedium:
            MediumAlarmWidgetView(entry: entry)
        case .systemSmall:
            SmallAlarmWidgetView(entry: entry)
        default:
            VStack {
                Text(entry.date, style: .time)
                Text(entry.configuration.favoriteEmoji)
            }
        }
    }
}

private struct SmallAlarmWidgetView: View {
    let entry: SimpleEntry

    var body: some View {
        ZStack {
            Image("CRockWidgetBigBackground")
                .resizable()
                .scaledToFill()

            Image(faceImageName)
                .resizable()
                .scaledToFit()
                .frame(width: 132, height: 84)
                .padding(.top, 22)
                .padding(.bottom, 57)
                .padding(.horizontal, 16)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.35), value: faceImageName)
        }
        .clipped()
    }

    private var faceImageName: String {
        let phase = (Int(entry.date.timeIntervalSince1970) / 3) % 4
        switch phase {
        case 1:
            return "CRockFace2"
        case 3:
            return "CRockFace3"
        default:
            return "CRockFace1"
        }
    }
}

private struct MediumAlarmWidgetView: View {
    let entry: SimpleEntry

    var body: some View {
        ZStack {
            Image(dailyBackgroundImageName)
                .resizable()
                .scaledToFill()

            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(statusText)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.62))
                        .lineLimit(2)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 12)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.amPm)
                            .font(.system(size: 20, weight: .bold))

                        Text(entry.timeText)
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(entry.isEnabled ? Color(red: 69 / 255, green: 69 / 255, blue: 69 / 255) : Color(red: 117 / 255, green: 117 / 255, blue: 117 / 255))
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                    .padding(.bottom, 2)

                    Button(intent: ToggleAlarmIntent()) {
                        WidgetToggle(
                            isOn: entry.isEnabled,
                            size: .init(
                                trackWidth: 82,
                                trackHeight: 36,
                                thumbWidth: 50,
                                thumbHeight: 30,
                                inset: 3
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(entry.isEnabled ? "CRockAlarmOn" : "CRockAlarmOff")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 121)
                    .padding(.trailing, 15)
            }
            .padding(.all, 18)
        }
        .clipped()
    }

    private var dailyBackgroundImageName: String {
        let weekday = Calendar.current.component(.weekday, from: entry.date)
        // weekday: 1 = Sun, 2 = Mon, 3 = Tue, 4 = Wed, 5 = Thu, 6 = Fri, 7 = Sat
        switch weekday {
        case 1: return "crock_sun_background"
        case 2: return "crock_mon_background"
        case 3: return "crock_tue_background"
        case 4: return "crock_wed_background"
        case 5: return "crock_thu_background"
        case 6: return "crock_fri_background"
        case 7: return "crock_sat_background"
        default: return "CRockWidgetBigBackground"
        }
    }

    private var statusText: String {
        if entry.isEnabled {
            return alarmRemainingText(from: entry.date)
        } else {
            return NSLocalizedString("widget_alarm_setup_prompt", comment: "스위치를 눌러 알람을 설정해주세요")
        }
    }

    private func alarmRemainingText(from date: Date) -> String {
        let calendar = Calendar.current
        let hour = hour24(from: entry.amPm, timeText: entry.timeText)
        let minute = Int(entry.timeText.split(separator: ":").last ?? "0") ?? 0

        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = minute

        guard var alarmDate = calendar.date(from: components) else {
            return NSLocalizedString("widget_alarm_on_message", comment: "알람이 울려요")
        }

        if alarmDate <= date {
            alarmDate = calendar.date(byAdding: .day, value: 1, to: alarmDate) ?? alarmDate
        }

        let diff = calendar.dateComponents([.hour, .minute], from: date, to: alarmDate)
        return String(
            format: NSLocalizedString("widget_alarm_remaining_format", comment: "%d시간 %d분 뒤에 알람이 울려요"),
            diff.hour ?? 0,
            diff.minute ?? 0
        )
    }

    private func hour24(from amPm: String, timeText: String) -> Int {
        let hour12 = Int(timeText.split(separator: ":").first ?? "7") ?? 7
        let isPM = amPm == NSLocalizedString("alarm_pm", comment: "오후")

        if isPM {
            return hour12 == 12 ? 12 : hour12 + 12
        } else {
            return hour12 == 12 ? 0 : hour12
        }
    }
}

private struct WidgetToggle: View {
    struct Size {
        let trackWidth: CGFloat
        let trackHeight: CGFloat
        let thumbWidth: CGFloat
        let thumbHeight: CGFloat
        let inset: CGFloat
    }

    let isOn: Bool
    let size: Size

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? Color.black.opacity(0.62) : Color.gray.opacity(0.72))

            Capsule()
                .fill(Color.white)
                .frame(width: size.thumbWidth, height: size.thumbHeight)
                .padding(size.inset)
        }
        .frame(width: size.trackWidth, height: size.trackHeight)
    }
}

struct CRockWidget: Widget {
    private let supportedFamilies: [WidgetFamily] = [.accessoryCircular, .systemSmall, .systemMedium]
    
    let kind: String = "CRockWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            CRockWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .supportedFamilies(supportedFamilies)
        .contentMarginsDisabled()
    }
}

extension ConfigurationAppIntent {
    fileprivate static var smiley: ConfigurationAppIntent {
        let intent = ConfigurationAppIntent()
        intent.favoriteEmoji = "😀"
        return intent
    }
    
    fileprivate static var starEyes: ConfigurationAppIntent {
        let intent = ConfigurationAppIntent()
        intent.favoriteEmoji = "🤩"
        return intent
    }
}

#Preview(as: .accessoryCircular) {
    CRockWidget()
} timeline: {
    SimpleEntry(date: .now, configuration: .smiley, isEnabled: false, amPm: "", timeText: "07:00")
}

#Preview(as: .systemMedium) {
    CRockWidget()
} timeline: {
    SimpleEntry(date: .now, configuration: .smiley, isEnabled: true, amPm: "오전", timeText: "07:00")
}

#Preview(as: .systemSmall) {
    CRockWidget()
} timeline: {
    SimpleEntry(date: .now, configuration: .smiley, isEnabled: false, amPm: "오전", timeText: "07:00")
}
