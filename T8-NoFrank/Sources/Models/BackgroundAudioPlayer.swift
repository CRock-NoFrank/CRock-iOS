//
//  BackgroundAudioPlayer.swift
//  T8-NoFrank
//
//  Created by 문창재 on 1/27/26.
//

import AVFoundation
import Foundation
import UserNotifications
import MediaPlayer

class BackgroundAudioPlayer: ObservableObject {
    static let shared = BackgroundAudioPlayer()

    @Published var isPlaying = false
    @Published var isAlarmMode = false

    private var audioPlayer: AVAudioPlayer?
    private var alarmTime: Date?
    private var checkTimer: Timer?
    private var selectedWeekdays: Set<Int> = []
    private var originalSystemVolume: Float = 0.0
    private var volumeRestorationTimer: Timer?

    private init() {
        setupAudioSession()
        _ = AlarmCoordinator.shared // 인터럽트 옵저버 등록
    }

    // MARK: - AlarmKit 인터럽트 후 재생 복원 (AlarmCoordinator에서 호출)
    func resumeAfterInterruption() {
        if isAlarmMode {
            // AlarmKit이 강제 종료됐지만 알람은 아직 울려야 하는 상태
            // → 오디오 세션 복구 후 앱 오디오로 알람 재생 + 알림 발송
            setupAudioSession()
            audioPlayer?.volume = 1.0
            audioPlayer?.play()
            sendLocalNotification()
            print("🔔 AlarmKit 종료 감지 → 앱 오디오로 알람 재개")
        } else {
            audioPlayer?.play()
            audioPlayer?.volume = 0.0
        }
    }

    // MARK: - System Volume Control
    private func setSystemVolume(_ volume: Float) {
        let volumeView = MPVolumeView()
        if let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                slider.value = volume
            }
        }
        print("📢 System volume set to: \(Int(volume * 100))%")
    }

    private func getCurrentSystemVolume() -> Float {
        return AVAudioSession.sharedInstance().outputVolume
    }

    // MARK: - Audio Session Setup
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // playback: 백그라운드 재생 가능
            // mixWithOthers: 다른 앱 오디오와 섞이지 않음
            try audioSession.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers] // 여기에 .mixWithOthers 옵션 추가
            )
            try audioSession.setActive(true)
            print("🔊 Audio session setup successful")
        } catch {
            print("❌ Failed to set up audio session: \(error)")
        }
    }

    // MARK: - Start Silent Sound (무음 재생 시작)
    func startSilentSound(hour: Int, minute: Int, weekdays: Set<Int>) {
        self.selectedWeekdays = weekdays
        updateNextAlarmTime(hour: hour, minute: minute)

        // 앱 재시작 시 이전 종료 경고 노티 즉시 취소
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["appTerminationWarning"])

        playSilentSound()

        // 1초마다 알람 시간 체크
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkAlarmTime()
        }

        isPlaying = true
        print("🔇 Silent sound started. Next alarm: \(alarmTime?.formatted() ?? "nil")")
    }

    // MARK: - Play Silent Sound
    private func playSilentSound() {
        // 무음 톤 생성 (AVAudioEngine 사용)
        // 또는 기존 무음 파일 사용
        guard let soundURL = Bundle.main.url(forResource: "NotiSound28sec", withExtension: "caf") else {
            print("❌ Sound file not found")
            return
        }

        do {
            // 일단 알람 사운드를 매우 작은 볼륨으로 재생 (무음처럼)
            audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
            audioPlayer?.numberOfLoops = -1 // 무한 반복
            audioPlayer?.volume = 0.0 // 완전 무음
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            print("🔇 Silent mode playing (volume: 0.0)")
        } catch {
            print("❌ Failed to play silent sound: \(error)")
        }
    }

    // MARK: - Play Alarm Sound
    private func playAlarmSound() {
        // 저장된 볼륨 가져오기 (AppGroup 사용)
        let appGroupID = "group.CRockWidget"
        let savedVolume = UserDefaults(suiteName: appGroupID)?.double(forKey: "alarmVolume")

        print("📊 Saved volume from UserDefaults: \(savedVolume ?? -1)")

        let targetVolume = Float(savedVolume ?? 1.0)

        // 현재 시스템 볼륨 저장
        originalSystemVolume = getCurrentSystemVolume()
        print("💾 Original system volume: \(Int(originalSystemVolume * 100))%")

        // 시스템 볼륨을 설정한 값으로 변경
        setSystemVolume(targetVolume)

        isAlarmMode = true

        // 2초마다 시스템 볼륨을 지정 볼륨으로 복원 (사용자가 볼륨 내리는 것 방지)
        startVolumeRestorationTimer(targetVolume: targetVolume)

        if AlarmCoordinator.shared.isAlarmKitAvailable {
            // iOS 26+: AlarmKit UI + 앱 오디오로 사운드 재생
            // AlarmKit이 강제 종료돼도 앱 오디오가 이어받을 수 있도록 미리 재생
            setupAudioSession()
            audioPlayer?.volume = 1.0
            audioPlayer?.play()
            print("🔔 AlarmKit alarm fired, app audio also playing (target volume: \(Int(targetVolume * 100))%)")
        } else {
            // iOS <26: BackgroundAudioPlayer 소리 + 로컬 노티
        	// 앱 내부 볼륨은 최대로 설정
            audioPlayer?.volume = 1.0
            sendLocalNotification()
        	print("🔔 Alarm sound started (target volume: \(Int(targetVolume * 100))%)")
        }
    }

    // MARK: - Send Local Notification
    private func sendLocalNotification() {
        let content = UNMutableNotificationContent()
        content.title = "CRock"
        content.body = "돌 깨러가기 🪨"
        content.userInfo = ["targetScreen": "BreakingStone"]
        content.sound = UNNotificationSound(named: .init("NotiSound28sec.caf"))

        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "alarmNotification_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to send notification: \(error)")
            } else {
                print("📬 Notification sent successfully")
            }
        }
    }

    // MARK: - Volume Restoration Timer
    private func startVolumeRestorationTimer(targetVolume: Float) {
        volumeRestorationTimer?.invalidate()
        volumeRestorationTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isAlarmMode else { return }
            let currentVolume = self.getCurrentSystemVolume()
            if currentVolume < targetVolume {
                self.setSystemVolume(targetVolume)
                print("🔊 Volume restored: \(Int(currentVolume * 100))% → \(Int(targetVolume * 100))%")
            }
        }
    }

    private func stopVolumeRestorationTimer() {
        volumeRestorationTimer?.invalidate()
        volumeRestorationTimer = nil
    }

    // MARK: - App Termination Warning (Dead Man's Switch)
    private func scheduleTerminationWarning() {
        let center = UNUserNotificationCenter.current()
        // 이전 경고 노티 취소 후 1초 뒤로 재예약
        center.removePendingNotificationRequests(withIdentifiers: ["appTerminationWarning"])

        let content = UNMutableNotificationContent()
        content.title = "CRock"
        content.body = "앱이 종료되었어요. 알람이 울리지 않을 수 있어요!"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        let request = UNNotificationRequest(
            identifier: "appTerminationWarning",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    // MARK: - Check Alarm Time
    private func checkAlarmTime() {
        guard let alarmTime = alarmTime else { return }

        // 알람 울리는 중이 아닐 때만 종료 경고 노티 예약
        if !isAlarmMode {
            scheduleTerminationWarning()
        } else {
            // 알람 모드일 때는 경고 노티 취소
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: ["appTerminationWarning"])
        }

        let now = Date()

        // 알람 시간이 지났고, 아직 알람 모드가 아니라면
        if now >= alarmTime && !isAlarmMode {
            let currentWeekday = Calendar.current.component(.weekday, from: now)

            // 현재 요일이 선택된 요일에 포함되어 있는지 확인
            if selectedWeekdays.contains(currentWeekday) {
                playAlarmSound()
            } else {
                // 선택되지 않은 요일이면 다음 알람 시간 업데이트
                let comps = Calendar.current.dateComponents([.hour, .minute], from: alarmTime)
                updateNextAlarmTime(hour: comps.hour ?? 0, minute: comps.minute ?? 0)
            }
        }
    }

    // MARK: - Update Next Alarm Time
    private func updateNextAlarmTime(hour: Int, minute: Int) {
        let calendar = Calendar.current
        let now = Date()

        var match = DateComponents()
        match.hour = hour
        match.minute = minute
        match.second = 0

        // 다음 발생 요일 찾기
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

        // iOS 26+: AlarmKit 알람도 같이 스케줄
        if let nextDate = nextAlarmDate {
            AlarmCoordinator.shared.scheduleNextAlarm(date: nextDate)
        }

        print("📅 Next alarm time updated: \(nextAlarmDate?.formatted() ?? "nil")")
    }

    // MARK: - Stop Alarm and Back to Silent
    func stopAlarmAndBackToSilent() {
        guard isAlarmMode else { return }
        AlarmCoordinator.shared.cancelAlarm()

        // 볼륨 복원 타이머 중지
        stopVolumeRestorationTimer()

        // 시스템 볼륨을 원래대로 복원
        setSystemVolume(originalSystemVolume)
        print("🔄 System volume restored to: \(Int(originalSystemVolume * 100))%")

        // 알람 소리를 무음으로 전환
        audioPlayer?.volume = 0.0
        isAlarmMode = false

        // AlarmKit이 오디오 세션을 가져갔을 수 있으므로 복원
        AlarmCoordinator.shared.recoverAudioSession()

        print("🔍 stopAlarmAndBackToSilent: Before playSilentSound(), audioPlayer nil? \(audioPlayer == nil), isPlaying: \(audioPlayer?.isPlaying ?? false)")
        // 오디오가 항상 재생되도록 보장
        playSilentSound()
        print("🔍 stopAlarmAndBackToSilent: After playSilentSound(), audioPlayer nil? \(audioPlayer == nil), isPlaying: \(audioPlayer?.isPlaying ?? false)")

        // 다음 알람 시간 계산
        if let alarmTime = alarmTime {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: alarmTime)
            updateNextAlarmTime(hour: comps.hour ?? 0, minute: comps.minute ?? 0)
        }

        print("🔇 Alarm stopped, back to silent mode")
    }

    // MARK: - Stop All
    func stopAll() {
        AlarmCoordinator.shared.cancelAlarm()

        // 볼륨 복원 타이머 중지
        stopVolumeRestorationTimer()

        // 알람 모드였다면 시스템 볼륨 복원
        if isAlarmMode {
            setSystemVolume(originalSystemVolume)
            print("🔄 System volume restored to: \(Int(originalSystemVolume * 100))%")
        }

        audioPlayer?.stop()
        audioPlayer = nil
        checkTimer?.invalidate()
        checkTimer = nil
        isPlaying = false
        isAlarmMode = false
        alarmTime = nil

        // 알람 끄면 종료 경고 노티도 취소
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["appTerminationWarning"])

        print("🛑 Background audio player stopped")
    }
}
