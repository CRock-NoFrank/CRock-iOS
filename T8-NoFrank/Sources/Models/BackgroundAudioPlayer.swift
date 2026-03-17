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
    private var hasSwappedToSilent = false

    private init() {
        setupAudioSession()
        _ = AlarmCoordinator.shared // 인터럽트 옵저버 등록
        setupAppStateObservers()
    }

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

    // MARK: - AlarmKit 인터럽트 후 재생 복원 (AlarmCoordinator에서 호출)
    func resumeAfterInterruption() {
        if isAlarmMode {
            // AlarmKit이 강제 종료됐지만 알람은 아직 울려야 하는 상태
            // → 오디오 세션 복구 후 앱 오디오로 알람 재생 + 알림 발송
            setupAudioSession()
            let savedVolume = Float(UserDefaults(suiteName: "group.CRockWidget")?.double(forKey: "alarmVolume") ?? 1.0)
            audioPlayer?.volume = savedVolume
            audioPlayer?.play()
            sendLocalNotification()
            print("🔔 AlarmKit 종료 감지 → 앱 오디오로 알람 재개")
        } else {
            audioPlayer?.play()
            audioPlayer?.volume = 0.0
        }
    }

    // MARK: - System Volume Control
    func updateSystemVolume(to volume: Double) {
        let targetVolume = Float(volume)
        setSystemVolume(targetVolume)
        print("📢 System volume updated from app: \(Int(targetVolume * 100))%")
    }

    private func setSystemVolume(_ volume: Float) {
        // 메인 스레드에서 실행 보장
        DispatchQueue.main.async {
            let volumeView = MPVolumeView(frame: CGRect(x: -100, y: -100, width: 1, height: 1))
            volumeView.alpha = 0.01 // 거의 투명하게

            // 최상위 윈도우에 잠시 추가하여 시스템 볼륨 제어권 확보
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                window.addSubview(volumeView)

                // 레이아웃이 완료된 후 슬라이더를 찾아서 값 설정
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider {
                        slider.value = volume
                        print("📢 System volume successfully forced to: \(Int(volume * 100))%")
                    } else {
                        print("⚠️ MPVolumeView slider not found")
                    }

                    // 설정 후 제거
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        volumeView.removeFromSuperview()
                    }
                }
            }
        }
    }

    private func getCurrentSystemVolume() -> Float {
        return AVAudioSession.sharedInstance().outputVolume
    }

    // MARK: - Audio Session Setup
    private func setupAudioSession(withDucking: Bool = false) {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            var options: AVAudioSession.CategoryOptions = [.mixWithOthers]
            if withDucking {
                options.insert(.duckOthers)
            }
            
            // mode를 .videoChat으로 설정하면 시스템 알람과 섞일 때 더 강력한 우선순위를 가집니다.
            try audioSession.setCategory(
                .playAndRecord,
                mode: .videoChat,
                options: options
            )
            try audioSession.setActive(true)
            print("🔊 Audio session setup successful (mode: videoChat, ducking: \(withDucking))")
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

        // 시스템 볼륨을 설정한 값으로 변경 (Media Volume)
        setSystemVolume(targetVolume)

        isAlarmMode = true

        // 2초마다 시스템 볼륨을 지정 볼륨으로 복원 (사용자가 볼륨 내리는 것 방지)
        startVolumeRestorationTimer(targetVolume: targetVolume)

        if AlarmCoordinator.shared.isAlarmKitAvailable {
            // iOS 26+: AlarmKit UI를 띄우면서 앱의 미디어 소리가 주도권을 잡도록 함
            // .duckOthers를 사용하여 다른 시스템 소리(알람킷)를 억제
            setupAudioSession(withDucking: true)

            audioPlayer?.volume = targetVolume
            audioPlayer?.play()
            
            // 알람킷이 소리를 시작하며 세션을 가로채는 순간을 방어하기 위해
            // 0.1초 간격으로 30회(3초간) 세션 활성화를 반복 시도 (강력한 탈환)
            for i in 1...30 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.1) { [weak self] in
                    guard let self = self, self.isAlarmMode else { return }
                    
                    let session = AVAudioSession.sharedInstance()
                    try? session.setActive(true, options: .notifyOthersOnDeactivation)
                    
                    if self.audioPlayer?.isPlaying == false {
                        self.audioPlayer?.play()
                    }
                    
                    // 매번 볼륨 다시 강제 (사용자가 도중에 줄여도 다시 앱 볼륨으로 고정)
                    self.setSystemVolume(targetVolume)
                }
            }
            
            print("🔔 Media Volume Dominance active. App audio forced to: \(Int(targetVolume * 100))%")
        } else {
            // iOS <26: BackgroundAudioPlayer 소리 + 로컬 노티
            audioPlayer?.volume = targetVolume
            sendLocalNotification()
            print("🔔 Alarm sound started (target volume: \(Int(targetVolume * 100))%)")
        }
    }

    // MARK: - Send Local Notification
    private func sendLocalNotification() {
        let content = UNMutableNotificationContent()
        content.title = "CRock"
        content.body = NSLocalizedString("alarm_notification_body", comment: "돌 깨러가기 🪨")
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
        // 0.5초마다 더 자주 체크하여 기기 시스템 볼륨을 강력하게 고정 (알라미 방식)
        volumeRestorationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, self.isAlarmMode else { return }
            
            let currentVolume = self.getCurrentSystemVolume()
            // 사용자가 수동으로 볼륨을 내리거나, 시스템이 알람 볼륨을 다르게 가져가려고 할 때 강제로 앱 설정값으로 복원
            if abs(currentVolume - targetVolume) > 0.05 {
                self.setSystemVolume(targetVolume)
                print("🔊 Volume Auto-Enforced: \(Int(currentVolume * 100))% → \(Int(targetVolume * 100))%")
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

        // 알람 울리기 2초 전, 앱이 살아있다면 알람킷을 무음으로 재예약 (UI 유지용)
        if now >= alarmTime.addingTimeInterval(-2.0) && now < alarmTime && !isAlarmMode {
            if !hasSwappedToSilent {
                print("⏳ Alarm almost due: swapping AlarmKit to silent to prioritize app audio.")
                // 앱이 살아있으므로 AlarmKit은 무음으로 울리게 하여 UI만 띄우고,
                // 실제 소리는 BackgroundAudioPlayer가 미디어 볼륨으로 재생함
                AlarmKitAvailability.scheduleAlarmIfAvailable(date: alarmTime, isSilent: true)
                hasSwappedToSilent = true
            }
        }

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
            hasSwappedToSilent = false
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

        // 기본적으로는 소리가 나는 알람으로 예약 (앱 종료 시 대비)
        if let nextDate = nextAlarmDate {
            AlarmKitAvailability.scheduleAlarmIfAvailable(date: nextDate, isSilent: false)
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
