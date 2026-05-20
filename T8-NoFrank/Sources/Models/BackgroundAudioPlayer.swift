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
import UIKit

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

    // iOS 13+에서는 MPVolumeView가 view hierarchy에 attach되어 있어야 system volume 변경이 먹힘.
    // 화면 밖 1x1 hidden view로 key window에 한 번 부착해 재사용.
    private lazy var persistentVolumeView: MPVolumeView = {
        let v = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
        v.isHidden = false
        v.alpha = 0.001
        return v
    }()
    private var volumeViewAttached = false

    private static let appGroupID = "group.CRockWidget"
    private static let isAlarmRingingKey = "isAlarmRinging"
    private static let alarmRingingTimestampKey = "alarmRingingTimestamp"
    private static let originalVolumeKey = "originalSystemVolume"
    private static let originalRingerVolumeKey = "originalRingerVolume"

    private var originalRingerVolume: Float = 1.0
    // Burst 노티 — UNCalendarNotificationTrigger로 매 분 0/2/4/.../58초마다 발동.
    // 시계 기반이라 알람 fire/강제 종료 시점 무관하게 ≤2초 안에 첫 노티 + 영원히 균일 반복.
    private static let burstCount = 30
    private static let burstIntervalSec: TimeInterval = 2
    private static let burstPrefix = "ALARM_BURST_"
    private static let alarmSoundName = "stone2_1.caf"
    private static let alarmRingingMaxDurationSec: TimeInterval = 1800  // 30분 영속화 만료

    private init() {
        setupAudioSession()
        setupInterruptionObserver()
    }

    // MARK: - System Volume Control
    /// 시스템 볼륨 강제 설정. iOS 11.4+에서 작동하는 검증된 방식:
    /// 1) MPVolumeView를 view hierarchy에 attach (key window의 hidden subview)
    /// 2) 내부 MPVolumeSlider를 NSStringFromClass로 정확히 식별
    /// 3) `.value =` 대신 `setValue(_:animated:)` 사용 (이게 진짜 시스템 볼륨을 바꿈)
    private func setSystemVolume(_ volume: Float) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.attachVolumeViewIfNeeded()
            guard let slider = self.findMPVolumeSlider(in: self.persistentVolumeView) else {
                print("⚠️ MPVolumeSlider not found in persistent view")
                return
            }
            slider.setValue(volume, animated: false)
        }
    }

    /// 첫 호출 시 key window에 한 번만 attach.
    private func attachVolumeViewIfNeeded() {
        guard !volumeViewAttached else { return }
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
            .first ?? UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.windows.first })
            .first else { return }
        window.addSubview(persistentVolumeView)
        volumeViewAttached = true
        print("✅ MPVolumeView attached to key window")
    }

    /// MPVolumeView 내부 hierarchy를 재귀 탐색해 MPVolumeSlider (private subclass of UISlider) 찾음.
    /// `is UISlider` 캐스팅으론 못 잡힘 — 클래스명으로 정확히 식별해야 함.
    private func findMPVolumeSlider(in view: UIView) -> UISlider? {
        for sub in view.subviews {
            if NSStringFromClass(type(of: sub)) == "MPVolumeSlider",
               let slider = sub as? UISlider {
                return slider
            }
            if let nested = findMPVolumeSlider(in: sub) {
                return nested
            }
        }
        return nil
    }

    private func getCurrentSystemVolume() -> Float {
        return AVAudioSession.sharedInstance().outputVolume
    }

    // MARK: - Audio Session Interruption Handling
    private func setupInterruptionObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc private func handleAudioInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            print("🔇 Audio session interrupted (phone call, Siri, etc.)")

        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)

            if options.contains(.shouldResume), isPlaying {
                print("🔊 Audio session interruption ended - restoring")
                restoreAudioSession()
            }

        @unknown default:
            break
        }
    }

    func restoreAudioSession() {
        guard isPlaying else { return }
        setupAudioSession()
        audioPlayer?.play()
        print("🔊 Audio session restored")
    }

    // MARK: - Audio Session Setup
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // mixWithOthers: 다른 앱(유튜브, 음악 등)이 재생 중에도 오디오 세션을 유지
            // → 인터럽트로 인한 앱 Suspend를 방지하여 Dead Man's Switch 타이머가 멈추지 않음
            // 무음(0.0) 재생이므로 다른 앱 오디오에 영향 없음
            try audioSession.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
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

        // 이전 사이클의 잔존 burst 노티 정리.
        // UNCalendar(repeats:true) burst는 명시 cancel 전까지 펜딩 풀에 영구 잔존하므로,
        // 직전 알람 fire 후 강제 종료된 경우 좀비 30개가 weeklyBurst와 합쳐져 64개 한도를
        // 초과해 termination warning 등록이 거부되는 문제를 사전 차단.
        cancelAlarmBurst()

        playSilentSound()

        // 1초마다 알람 시간 체크
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkAlarmTime()
        }

        isPlaying = true
        print("🔇 Silent sound started. Next alarm: \(alarmTime?.formatted() ?? "nil")")

        // iOS 26+: AlarmKit weekly alarm 등록. 시스템이 자체 ringing 처리하므로 burst 노티 불필요.
        // Silent audio loop은 유지 — 알람 시간에 시스템 볼륨 오버라이드 위해 앱을 살아있게 함.
        if #available(iOS 26.0, *) {
            Task {
                await AlarmKitManager.shared.scheduleMainAlarm(
                    hour: hour, minute: minute, weekdays: weekdays
                )
                AlarmKitManager.shared.startObserving()
            }
        }
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
    func playAlarmSound() {
        // 저장된 볼륨 가져오기 (AppGroup 사용)
        let savedVolume = UserDefaults(suiteName: Self.appGroupID)?.double(forKey: "alarmVolume")

        print("📊 Saved volume from UserDefaults: \(savedVolume ?? -1)")

        let targetVolume = Float(savedVolume ?? 1.0)

        // 현재 시스템 볼륨 저장 (재실행 복원용으로 UserDefaults에도 저장)
        originalSystemVolume = getCurrentSystemVolume()
        UserDefaults(suiteName: Self.appGroupID)?.set(
            Double(originalSystemVolume), forKey: Self.originalVolumeKey
        )
        print("💾 Original system volume: \(Int(originalSystemVolume * 100))%")

        // iOS 26+: AlarmKit은 Ringtone 채널로 재생 → 시스템 벨소리 볼륨을 따름.
        // RingerVolumeController (private AVSystemController API)로 Ringtone 볼륨을 직접 set해서
        // AlarmKit 사운드가 유저 설정 볼륨으로 울리게 함. (alerting은 stop하지 않음)
        if #available(iOS 26.0, *) {
            if let currentRinger = RingerVolumeController.shared.getVolume(for: .ringtone) {
                originalRingerVolume = currentRinger
                UserDefaults(suiteName: Self.appGroupID)?
                    .set(Double(currentRinger), forKey: Self.originalRingerVolumeKey)
                print("💾 Original Ringtone volume: \(Int(currentRinger * 100))%")
            }
            let ok = RingerVolumeController.shared.setVolume(targetVolume, for: .ringtone)
            print("📢 Ringtone volume set to \(Int(targetVolume * 100))% — success=\(ok)")
        }

        // AlarmKit이 audio session 우선권을 빼앗았을 가능성 → 명시적으로 .playback (no mix) 카테고리로
        // 재설정 + reactivate해서 우리 in-app audio가 미디어 채널로 큰 소리 낼 수 있게 함.
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true, options: [.notifyOthersOnDeactivation])
            print("🔊 Audio session reactivated for alarm playback")
        } catch {
            print("❌ Failed to reactivate audio session: \(error)")
        }

        // 시스템 볼륨을 설정한 값으로 즉시 + 0.05초 / 0.1초 / 0.2초 후 반복 set —
        // MPVolumeSlider attach 직후 setValue가 한 번엔 안 먹는 케이스 대비.
        setSystemVolume(targetVolume)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.setSystemVolume(targetVolume)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.setSystemVolume(targetVolume)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.setSystemVolume(targetVolume)
        }

        // audioPlayer를 무조건 새로 생성 — silent loop 상태에서 volume만 바꾸는 방식이
        // iOS 26에서 안 들리는 케이스 대비. 기존 player 정지 후 fresh instance로 교체.
        audioPlayer?.stop()
        audioPlayer = nil

        guard let soundURL = Bundle.main.url(forResource: "NotiSound28sec", withExtension: "caf") else {
            print("❌ Sound file not found")
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: soundURL)
            player.numberOfLoops = -1
            player.volume = 1.0
            player.prepareToPlay()
            player.play()
            audioPlayer = player
            print("🔔 Fresh AVAudioPlayer created and playing — volume=\(player.volume), isPlaying=\(player.isPlaying)")
        } catch {
            print("❌ Failed to create audio player: \(error)")
            return
        }
        isAlarmMode = true

        // 알람 상태 영속화 (강제 종료 후 복원용)
        persistAlarmRinging(true)

        // 2초마다 시스템 볼륨을 지정 볼륨으로 복원 (사용자가 볼륨 내리는 것 방지)
        startVolumeRestorationTimer(targetVolume: targetVolume)

        // iOS 26+: AlarmKit이 시스템 알림/burst 역할을 대체. 로컬 노티 + UNCalendar burst 모두 생략.
        // AlarmKit alerting은 계속 ring (Ringtone 채널 볼륨은 위에서 유저 설정값으로 강제 set됨).
        // iOS 26 미만: 기존대로 로컬 노티 1개 + burst 노티 30개 예약.
        if #available(iOS 26.0, *) {
            AlarmKitManager.markAlarmFired()
        } else {
            sendLocalNotification()
            scheduleAlarmBurst()
        }

        print("🔔 Alarm sound started (target volume: \(Int(targetVolume * 100))%)")
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

    // MARK: - Alarm Ringing Persistence
    private func persistAlarmRinging(_ ringing: Bool) {
        let ud = UserDefaults(suiteName: Self.appGroupID)
        ud?.set(ringing, forKey: Self.isAlarmRingingKey)
        if ringing {
            ud?.set(Date().timeIntervalSince1970, forKey: Self.alarmRingingTimestampKey)
        } else {
            ud?.removeObject(forKey: Self.alarmRingingTimestampKey)
            ud?.removeObject(forKey: Self.originalVolumeKey)
            ud?.removeObject(forKey: Self.originalRingerVolumeKey)
        }
    }

    /// 강제 종료 후 재실행 시 알람 상태 확인 (30분 이내만 유효)
    static func isAlarmRingingPersisted() -> Bool {
        let ud = UserDefaults(suiteName: appGroupID)
        guard ud?.bool(forKey: isAlarmRingingKey) == true,
              let timestamp = ud?.double(forKey: alarmRingingTimestampKey),
              timestamp > 0
        else { return false }

        let elapsed = Date().timeIntervalSince1970 - timestamp
        return elapsed < alarmRingingMaxDurationSec
    }

    /// 영속화된 알람 상태 초기화
    static func clearAlarmRingingPersistence() {
        let ud = UserDefaults(suiteName: appGroupID)
        ud?.set(false, forKey: isAlarmRingingKey)
        ud?.removeObject(forKey: alarmRingingTimestampKey)
        ud?.removeObject(forKey: originalVolumeKey)
        ud?.removeObject(forKey: originalRingerVolumeKey)
    }

    /// 영속화된 원래 시스템 볼륨 복원 (미디어 + Ringtone 둘 다).
    /// 강제 종료 후 재실행 시 알람 끄면 원래 볼륨으로 돌려놓기 위함.
    func restoreOriginalVolumeFromPersistence() {
        if let saved = UserDefaults(suiteName: Self.appGroupID)?.double(forKey: Self.originalVolumeKey),
           saved > 0 {
            originalSystemVolume = Float(saved)
        } else {
            originalSystemVolume = getCurrentSystemVolume()
        }
        if let savedRinger = UserDefaults(suiteName: Self.appGroupID)?.double(forKey: Self.originalRingerVolumeKey),
           savedRinger > 0 {
            originalRingerVolume = Float(savedRinger)
        } else if #available(iOS 26.0, *),
                  let currentRinger = RingerVolumeController.shared.getVolume(for: .ringtone) {
            originalRingerVolume = currentRinger
        }
    }

    // MARK: - Alarm Burst Notifications (강제 종료 대비)

    /// UNCalendarNotificationTrigger로 매 분 0, 2, 4, ..., 58초에 발동되는 노티 30개 등록.
    /// 시계 기반이라 알람 fire/강제 종료 시점 무관하게 ≤2초 안에 첫 노티 + 영원히 매 2초 균일 반복.
    /// 앱 살아있는 동안에도 발동되지만 willPresent에서 prefix 필터링으로 화면/사운드 차단됨.
    private func scheduleAlarmBurst() {
        let center = UNUserNotificationCenter.current()

        // 중복 방지 — 기존 burst cancel 후 새로 등록
        let ids = (0..<Self.burstCount).map { "\(Self.burstPrefix)\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)

        for i in 0..<Self.burstCount {
            let content = UNMutableNotificationContent()
            content.title = "CRock"
            content.body = NSLocalizedString("alarm_notification_body", comment: "돌 깨러가기 🪨")
            content.userInfo = ["targetScreen": "BreakingStone"]
            content.sound = UNNotificationSound(named: .init(Self.alarmSoundName))

            if #available(iOS 15.0, *) {
                content.interruptionLevel = .timeSensitive
            }

            // 매 분의 0, 2, 4, ..., 58초에 발동 (30개 × 2초 = 60초 사이클)
            var components = DateComponents()
            components.second = Int(Double(i) * Self.burstIntervalSec)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

            let request = UNNotificationRequest(
                identifier: "\(Self.burstPrefix)\(i)",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
        print("📬 Alarm burst scheduled: \(Self.burstCount) calendar notifications (every \(Int(Self.burstIntervalSec))s)")
    }

    /// burst 노티 cancel + 알림센터 정리. 돌 깨기 성공 시 호출.
    /// `appTerminationWarning` 등 다른 노티는 보존됨 (식별자 prefix로 정확히 분리).
    func cancelAlarmBurst() {
        let ids = (0..<Self.burstCount).map { "\(Self.burstPrefix)\($0)" }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
        print("🗑️ Alarm burst cancelled (\(ids.count))")
    }

    /// 앱 재진입 시 알람 모드 비활성인데 burst 노티가 살아있는 좀비 상태 정리.
    /// repeats:true는 명시적 cancel 전까지 영원히 발동되므로 안전장치 필수.
    func cleanupZombieBurstIfNotAlarming() {
        guard !isAlarmMode else { return }
        cancelAlarmBurst()
    }

    // MARK: - Volume Restoration Timer
    /// 0.2초 간격으로 무조건 미디어 + Ringtone 볼륨 둘 다 갈김. 현재 볼륨 확인 안 함.
    /// AlarmKit / 시스템이 우리 설정을 덮어쓰는 케이스 대비.
    private func startVolumeRestorationTimer(targetVolume: Float) {
        volumeRestorationTimer?.invalidate()
        volumeRestorationTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self = self, self.isAlarmMode else { return }
            self.setSystemVolume(targetVolume)
            if #available(iOS 26.0, *) {
                _ = RingerVolumeController.shared.setVolume(targetVolume, for: .ringtone)
            }
        }
    }

    private func stopVolumeRestorationTimer() {
        volumeRestorationTimer?.invalidate()
        volumeRestorationTimer = nil
    }

    // MARK: - App Termination Warning (Dead Man's Switch)
    private func scheduleTerminationWarning() {
        // iOS 26+ AlarmKit이 앱 강제 종료 후에도 시스템 레벨에서 알람을 울리므로 경고 불필요.
        if #available(iOS 26.0, *) {
            return
        }

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
            // 알람 모드일 때는 경고 노티 취소 (burst는 시계 기반 1회 등록이라 재예약 불필요)
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
        print("📅 Next alarm time updated: \(nextAlarmDate?.formatted() ?? "nil")")
    }

    // MARK: - Stop Alarm and Back to Silent
    func stopAlarmAndBackToSilent() {
        guard isAlarmMode else { return }

        // 볼륨 복원 타이머 중지
        stopVolumeRestorationTimer()

        // 시스템 미디어 볼륨 + Ringtone 볼륨 모두 원래대로 복원
        setSystemVolume(originalSystemVolume)
        if #available(iOS 26.0, *) {
            _ = RingerVolumeController.shared.setVolume(originalRingerVolume, for: .ringtone)
            print("🔄 Ringtone volume restored to: \(Int(originalRingerVolume * 100))%")
        }
        print("🔄 System volume restored to: \(Int(originalSystemVolume * 100))%")

        // 알람용 fresh AVAudioPlayer 정지 후 silent loop을 재구성 — audio session도
        // mixWithOthers 옵션으로 다시 setup해 다른 앱 오디오와 공존 가능 상태로 복귀.
        audioPlayer?.stop()
        audioPlayer = nil
        setupAudioSession()
        playSilentSound()
        isAlarmMode = false

        // 영속화 상태 초기화 + burst 취소
        persistAlarmRinging(false)
        cancelAlarmBurst()

        // iOS 26+: alerting 중인 AlarmKit 알람 + backup 알람 모두 정지.
        // weekly recurrence는 다음 주에 자동 재예약되므로 main alarm 자체 cancel은 하지 않음.
        if #available(iOS 26.0, *) {
            Task {
                await AlarmKitManager.shared.stopAlertingAlarms()
            }
            AlarmKitManager.shared.cancelBackupAlarm()
            AlarmKitManager.clearAlarmFiredMark()
        }

        // 다음 알람 시간 계산
        if let alarmTime = alarmTime {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: alarmTime)
            updateNextAlarmTime(hour: comps.hour ?? 0, minute: comps.minute ?? 0)
        }

        print("🔇 Alarm stopped, back to silent mode")
    }

    // MARK: - Stop All
    func stopAll() {
        // 볼륨 복원 타이머 중지
        stopVolumeRestorationTimer()

        // 알람 모드였다면 시스템 미디어 + Ringtone 볼륨 모두 복원
        if isAlarmMode {
            setSystemVolume(originalSystemVolume)
            print("🔄 System volume restored to: \(Int(originalSystemVolume * 100))%")
            if #available(iOS 26.0, *) {
                _ = RingerVolumeController.shared.setVolume(originalRingerVolume, for: .ringtone)
                print("🔄 Ringtone volume restored to: \(Int(originalRingerVolume * 100))%")
            }
        }

        audioPlayer?.stop()
        audioPlayer = nil
        checkTimer?.invalidate()
        checkTimer = nil
        isPlaying = false
        isAlarmMode = false
        alarmTime = nil

        // 영속화 상태 초기화 + burst 취소
        persistAlarmRinging(false)
        cancelAlarmBurst()

        // 알람 끄면 종료 경고 노티도 취소
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["appTerminationWarning"])

        // iOS 26+: AlarmKit 알람 전체 취소 (유저가 알람 자체를 off 했을 때만 호출되므로 main도 cancel)
        if #available(iOS 26.0, *) {
            AlarmKitManager.shared.cancelAllAlarms()
            AlarmKitManager.shared.stopObserving()
            AlarmKitManager.clearAlarmFiredMark()
        }

        print("🛑 Background audio player stopped")
    }
}
