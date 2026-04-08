//
//  BackgroundAudioPlayerIOS26.swift
//  T8-NoFrank
//
//  Created by JiJooMaeng on 2/10/26.
//
//  iOS 26+ 전용 BackgroundAudioPlayer 서브클래스

#if canImport(AlarmKit)
import AVFoundation
import Foundation
import UIKit
import UserNotifications

@available(iOS 26.0, *)
final class BackgroundAudioPlayerIOS26: BackgroundAudioPlayer {

    private var hasSwappedToSilent = false

    override init() {
        super.init()
        _ = AlarmCoordinator.shared // 인터럽트 옵저버 등록
        setupAppStateObservers()
    }

    // MARK: - App State Observers (AlarmKit 재예약용)
    private func setupAppStateObservers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // 앱이 백그라운드로 가면 혹시 모를 종료에 대비해 알람을 다시 소리 나는 모드로 변경
            self?.refreshAlarmSoundMode(isSilent: false)
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // 앱이 다시 포그라운드로 오면 다시 무음 스왑 대기 상태로 초기화
            self?.hasSwappedToSilent = false
        }
    }

    private func refreshAlarmSoundMode(isSilent: Bool) {
        guard let alarmTime = alarmTime, !isAlarmMode else { return }
        AlarmKitAvailability.scheduleAlarmIfAvailable(date: alarmTime, isSilent: isSilent)
        print("🔄 App state changed: Rescheduled AlarmKit (isSilent: \(isSilent))")
    }

    override func setupAudioSession(withDucking: Bool = false) {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            var options: AVAudioSession.CategoryOptions = [.mixWithOthers]
            if withDucking { options.insert(.duckOthers) }
            try audioSession.setCategory(.playAndRecord, mode: .videoChat, options: options)
            try audioSession.setActive(true)
            print("🔊 Audio session setup successful (ducking: \(withDucking))")
        } catch {
            print("❌ Failed to set up audio session: \(error)")
        }
    }

    // MARK: - 오디오 인터럽트 후 재생 복원 (전화 등 외부 인터럽트 대응)
    override func resumeAfterInterruption() {
        if isAlarmMode {
            // AlarmKit이 강제 종료됐지만 알람은 아직 울려야 하는 상태
            // → 오디오 세션 복구 후 앱 오디오로 알람 재생 + 알림 발송
            setupAudioSession()
            let savedVolume = Float(UserDefaults(suiteName: "group.CRockWidget")?.double(forKey: "alarmVolume") ?? 1.0)
            audioPlayer?.volume = savedVolume
            audioPlayer?.play()
            sendLocalNotification()
            print("🔔 인터럽트 종료 → 알람 재개")
        } else {
            audioPlayer?.play()
            audioPlayer?.volume = 0.0
        }
    }

// MARK: - Play Alarm Sound (AlarmKit 인터럽트 후 세션 재확립)
    override func playAlarmSound() {
        let appGroupID = "group.CRockWidget"
        let savedVolume = UserDefaults(suiteName: appGroupID)?.double(forKey: "alarmVolume")
        let targetVolume = Float(savedVolume ?? 1.0)
        print("📊 Saved volume from UserDefaults: \(savedVolume ?? -1)")

        isAlarmMode = true

        setupAudioSession(withDucking: true)
        audioPlayer?.volume = targetVolume
        audioPlayer?.play()

        for i in 1...30 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.1) { [weak self] in
                guard let self, self.isAlarmMode else { return }
                try? AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
                if self.audioPlayer?.isPlaying == false {
                    self.audioPlayer?.play()
                }
                self.audioPlayer?.volume = targetVolume
            }
        }

        startVolumeRestorationTimer(targetVolume: targetVolume)
        print("🔔 iOS 26+: audioPlayer.volume forced to \(Int(targetVolume * 100))%")
    }

    override func startVolumeRestorationTimer(targetVolume: Float) {
        volumeRestorationTimer?.invalidate()
        volumeRestorationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.isAlarmMode else { return }
            let currentPlayerVolume = self.audioPlayer?.volume ?? 0
            if abs(currentPlayerVolume - targetVolume) > 0.05 {
                self.audioPlayer?.volume = targetVolume
                print("🔊 Player Volume Auto-Enforced: \(Int(currentPlayerVolume * 100))% → \(Int(targetVolume * 100))%")
            }
        }
    }

    // MARK: - Check Alarm Time
    override func checkAlarmTime() {
        guard let alarmTime = alarmTime else { return }

        if !isAlarmMode {
            scheduleTerminationWarning()
        } else {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: ["appTerminationWarning"])
        }

        let now = Date()

        // 알람 울리기 2초 전, 앱이 살아있다면 알람킷을 무음으로 재예약 (UI 유지용)
        if now >= alarmTime.addingTimeInterval(-2.0) && now < alarmTime && !isAlarmMode {
            if !hasSwappedToSilent {
                print("⏳ Alarm almost due: swapping AlarmKit to silent to prioritize app audio.")
                AlarmKitAvailability.scheduleAlarmIfAvailable(date: alarmTime, isSilent: true)
                hasSwappedToSilent = true
            }
        }

        if now >= alarmTime && !isAlarmMode {
            let currentWeekday = Calendar.current.component(.weekday, from: now)

            if selectedWeekdays.contains(currentWeekday) {
                playAlarmSound()
            } else {
                let comps = Calendar.current.dateComponents([.hour, .minute], from: alarmTime)
                updateNextAlarmTime(hour: comps.hour ?? 0, minute: comps.minute ?? 0)
            }
            hasSwappedToSilent = false
        }
    }

    // MARK: - Update Next Alarm Time (AlarmKit 예약 포함)
    override func updateNextAlarmTime(hour: Int, minute: Int) {
        let calendar = Calendar.current
        let now = Date()

        var nextAlarmDate: Date?

        for dayOffset in 0..<7 {
            let checkDate = calendar.date(byAdding: .day, value: dayOffset, to: now)!
            let weekday = calendar.component(.weekday, from: checkDate)

            if selectedWeekdays.contains(weekday) {
                var comps = calendar.dateComponents([.year, .month, .day], from: checkDate)
                comps.hour = hour
                comps.minute = minute
                comps.second = 0

                if let candidateDate = calendar.date(from: comps),
                   candidateDate > now {
                    nextAlarmDate = candidateDate
                    break
                }
            }
        }

        self.alarmTime = nextAlarmDate

        if let nextDate = nextAlarmDate {
            AlarmKitAvailability.scheduleAlarmIfAvailable(date: nextDate, isSilent: false)
        }

        print("📅 Next alarm time updated: \(nextAlarmDate?.formatted() ?? "nil")")
    }

    // MARK: - Stop Alarm and Back to Silent
    override func stopAlarmAndBackToSilent() {
        guard isAlarmMode else { return }
        AlarmCoordinator.shared.cancelAlarm()

        stopVolumeRestorationTimer()

        audioPlayer?.volume = 0.0
        isAlarmMode = false

        AlarmCoordinator.shared.recoverAudioSession()
        playSilentSound()

        if let alarmTime = alarmTime {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: alarmTime)
            updateNextAlarmTime(hour: comps.hour ?? 0, minute: comps.minute ?? 0)
        }

        print("🔇 Alarm stopped, back to silent mode")
    }

    // MARK: - Stop All
    override func stopAll() {
        AlarmCoordinator.shared.cancelAlarm()

        stopVolumeRestorationTimer()

        audioPlayer?.stop()
        audioPlayer = nil
        checkTimer?.invalidate()
        checkTimer = nil
        isPlaying = false
        isAlarmMode = false
        alarmTime = nil

        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["appTerminationWarning"])

        print("🛑 Background audio player stopped")
    }
}
#endif  // canImport(AlarmKit)
