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
                return (enabled, "", NSLocalizedString("widget_no_alarm", comment: "없음"))
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
struct CRockWidget: Widget {
    private let supportedFamilies: [WidgetFamily] = [.accessoryCircular]
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
#Preview(as: .systemSmall) {
    CRockWidget()
} timeline: {
    SimpleEntry(date: .now, configuration: .smiley, isEnabled: false, amPm: "오전", timeText: "07:00")
}
