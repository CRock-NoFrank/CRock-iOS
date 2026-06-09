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

    private static let appGroupID = "group.CRockWidget"
    private static let isAlarmRingingKey = "isAlarmRinging"
    private static let alarmRingingTimestampKey = "alarmRingingTimestamp"
    private static let originalVolumeKey = "originalSystemVolume"
    // Burst 노티 — UNCalendarNotificationTrigger로 매 분 0/2/4/.../58초마다 발동.
    // 시계 기반이라 알람 fire/강제 종료 시점 무관하게 ≤2초 안에 첫 노티 + 영원히 균일 반복.
    private static let burstCount = 30
    private static let burstIntervalSec: TimeInterval = 2
    private static let burstPrefix = "ALARM_BURST_"
    private static let alarmSoundName = "stone2_1.caf"
    private static let alarmRingingMaxDurationSec: TimeInterval = 1800  // 30분 영속화 만료

    // MARK: - Dependencies (테스트에서 교체 가능)
    /// 노티 예약/제거는 이 게이트만 통해서 한다. 운영은 SystemNotificationScheduler,
    /// 테스트는 SpyNotificationScheduler를 주입.
    private let scheduler: NotificationScheduling

    /// 운영 빌드는 `.shared`만 사용. 테스트 빌드는 setupAudio=false로 오디오 세션 부작용 없이 생성한다.
    /// - Parameters:
    ///   - scheduler: 노티 스케줄링 의존성 (기본: 실제 UNUserNotificationCenter 호출)
    ///   - setupAudio: AVAudioSession/인터럽트 옵저버 셋업 여부 (테스트는 false 권장)
    init(
        scheduler: NotificationScheduling = SystemNotificationScheduler(),
        setupAudio: Bool = true
    ) {
        self.scheduler = scheduler
        if setupAudio {
            setupAudioSession()
            setupInterruptionObserver()
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
        scheduler.removePending(identifiers: ["appTerminationWarning"])

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

        // 시스템 볼륨을 설정한 값으로 변경
        setSystemVolume(targetVolume)

        // audioPlayer가 없으면 (강제 종료 후 재실행) 새로 생성
        if audioPlayer == nil {
            guard let soundURL = Bundle.main.url(forResource: "NotiSound28sec", withExtension: "caf") else {
                print("❌ Sound file not found")
                return
            }
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
                audioPlayer?.numberOfLoops = -1
                audioPlayer?.prepareToPlay()
                audioPlayer?.play()
            } catch {
                print("❌ Failed to create audio player: \(error)")
                return
            }
        }

        // 앱 내부 볼륨은 최대로 설정
        audioPlayer?.volume = 1.0
        isAlarmMode = true

        // 알람 상태 영속화 (강제 종료 후 복원용)
        persistAlarmRinging(true)

        // 2초마다 시스템 볼륨을 지정 볼륨으로 복원 (사용자가 볼륨 내리는 것 방지)
        startVolumeRestorationTimer(targetVolume: targetVolume)

        // 노티 1개만 전송
        sendLocalNotification()

        // 강제 종료 대비 burst 노티 예약 (UNCalendar 시계 기반, 매 2초 균일 무한 반복)
        scheduleAlarmBurst()

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

        scheduler.add(request)
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

    /// 영속화된 원래 시스템 볼륨 복원
    func restoreOriginalVolumeFromPersistence() {
        if let saved = UserDefaults(suiteName: Self.appGroupID)?.double(forKey: Self.originalVolumeKey),
           saved > 0 {
            originalSystemVolume = Float(saved)
        } else {
            originalSystemVolume = getCurrentSystemVolume()
        }
    }

    // MARK: - Alarm Burst Notifications (강제 종료 대비)
    /// internal: 테스트에서 직접 호출해 노티 예약 패턴(개수/트리거/ID)을 검증한다.
    /// UNCalendarNotificationTrigger로 매 분 0, 2, 4, ..., 58초에 발동되는 노티 30개 등록.
    /// 시계 기반이라 알람 fire/강제 종료 시점 무관하게 ≤2초 안에 첫 노티 + 영원히 매 2초 균일 반복.
    /// 앱 살아있는 동안에도 발동되지만 willPresent에서 prefix 필터링으로 화면/사운드 차단됨.
    func scheduleAlarmBurst() {
        // 중복 방지 — 기존 burst 제거 후 새로 등록 (scheduler 경유로 테스트에서 Spy 검증 가능)
        let ids = (0..<Self.burstCount).map { "\(Self.burstPrefix)\($0)" }
        scheduler.removePending(identifiers: ids)

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
            scheduler.add(request)
        }
        print("📬 Alarm burst scheduled: \(Self.burstCount) calendar notifications (every \(Int(Self.burstIntervalSec))s)")
    }

    /// burst 노티 cancel + 알림센터 정리. 돌 깨기 성공 시 호출.
    /// `appTerminationWarning` 등 다른 노티는 보존됨 (식별자 prefix로 정확히 분리).
    func cancelAlarmBurst() {
        let ids = (0..<Self.burstCount).map { "\(Self.burstPrefix)\($0)" }
        scheduler.removePending(identifiers: ids)
        scheduler.removeDelivered(identifiers: ids)
        print("🗑️ Alarm burst cancelled (\(ids.count))")
    }

    /// 앱 재진입 시 알람 모드 비활성인데 burst 노티가 살아있는 좀비 상태 정리.
    /// repeats:true는 명시적 cancel 전까지 영원히 발동되므로 안전장치 필수.
    func cleanupZombieBurstIfNotAlarming() {
        guard !isAlarmMode else { return }
        cancelAlarmBurst()
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
    /// internal: 테스트에서 직접 호출해 종료 경고 노티 등록 패턴을 검증한다.
    func scheduleTerminationWarning() {
        // 이전 경고 노티 취소 후 1초 뒤로 재예약
        scheduler.removePending(identifiers: ["appTerminationWarning"])

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
        scheduler.add(request)
    }

    // MARK: - Alarm Decision (순수 함수 — 단위 테스트 대상)
    enum AlarmCheckResult: Equatable {
        case ring                    // 알람 사운드 재생
        case rescheduleToNextWeekday // 미선택 요일 → 다음 알람 시각으로
        case wait                    // 알람 시각 전이거나 이미 알람 모드
    }

    /// 알람을 울려야 하는지 판정하는 순수 함수. 외부 상태를 읽지 않아 결정적이고 테스트 가능.
    static func evaluateAlarm(
        now: Date,
        alarmTime: Date,
        isAlarmMode: Bool,
        selectedWeekdays: Set<Int>,
        calendar: Calendar = .current
    ) -> AlarmCheckResult {
        guard now >= alarmTime, !isAlarmMode else { return .wait }
        let weekday = calendar.component(.weekday, from: now)
        return selectedWeekdays.contains(weekday) ? .ring : .rescheduleToNextWeekday
    }

    // MARK: - Check Alarm Time
    private func checkAlarmTime() {
        guard let alarmTime = alarmTime else { return }

        // 알람 울리는 중이 아닐 때만 종료 경고 노티 예약
        if !isAlarmMode {
            scheduleTerminationWarning()
        } else {
            // 알람 모드일 때는 경고 노티 취소 (burst는 시계 기반 1회 등록이라 재예약 불필요)
            scheduler.removePending(identifiers: ["appTerminationWarning"])
        }

        switch Self.evaluateAlarm(
            now: Date(),
            alarmTime: alarmTime,
            isAlarmMode: isAlarmMode,
            selectedWeekdays: selectedWeekdays
        ) {
        case .ring:
            playAlarmSound()
        case .rescheduleToNextWeekday:
            let comps = Calendar.current.dateComponents([.hour, .minute], from: alarmTime)
            updateNextAlarmTime(hour: comps.hour ?? 0, minute: comps.minute ?? 0)
        case .wait:
            break
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

        // 시스템 볼륨을 원래대로 복원
        setSystemVolume(originalSystemVolume)
        print("🔄 System volume restored to: \(Int(originalSystemVolume * 100))%")

        // 알람 소리를 무음으로 전환
        audioPlayer?.volume = 0.0
        isAlarmMode = false

        // 영속화 상태 초기화 + burst 취소
        persistAlarmRinging(false)
        cancelAlarmBurst()

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

        // 영속화 상태 초기화 + burst 취소
        persistAlarmRinging(false)
        cancelAlarmBurst()

        // 알람 끄면 종료 경고 노티도 취소
        scheduler.removePending(identifiers: ["appTerminationWarning"])

        print("🛑 Background audio player stopped")
    }
}
