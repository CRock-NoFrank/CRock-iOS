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
    private static let alarmRingingMaxDurationSec: TimeInterval = 1800  // 30분 영속화 만료

    // MARK: - Dependencies (테스트에서 교체 가능)
    /// 노티 예약/제거는 이 게이트만 통해서 한다. 운영은 SystemNotificationScheduler,
    /// 테스트는 SpyNotificationScheduler를 주입.
    private let scheduler: NotificationScheduling

    /// 버전별 "알람 깨우기 방식". BackgroundAudioPlayer는 이 역할에만 의존하고
    /// 실제 iOS 18 / iOS 26 여부는 모른다. (판별은 AlarmPlatformFactory가 한다)
    private let alarmPlatform: AlarmPlatform

    /// 운영 빌드는 `.shared`만 사용. 테스트 빌드는 setupAudio=false로 오디오 세션 부작용 없이 생성한다.
    /// - Parameters:
    ///   - scheduler: 노티 스케줄링 의존성 (기본: 실제 UNUserNotificationCenter 호출)
    ///   - alarmPlatform: 알람 깨우기 방식 (기본: 현재 OS에 맞는 구현체를 Factory가 생성)
    ///   - setupAudio: AVAudioSession/인터럽트 옵저버 셋업 여부 (테스트는 false 권장)
    init(
        scheduler: NotificationScheduling = SystemNotificationScheduler(),
        alarmPlatform: AlarmPlatform? = nil,
        setupAudio: Bool = true
    ) {
        self.scheduler = scheduler
        self.alarmPlatform = alarmPlatform ?? AlarmPlatformFactory.make(scheduler: scheduler)
        if setupAudio {
            setupAudioSession()
            setupInterruptionObserver()
        }
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
        scheduler.removePending(identifiers: ["appTerminationWarning"])

        // 직전 사이클에서 남은 예약 잔여물 정리 (iOS 18은 좀비 burst 노티 제거).
        alarmPlatform.clearStaleAlarms()

        playSilentSound()

        // 1초마다 알람 시간 체크
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkAlarmTime()
        }

        isPlaying = true
        print("🔇 Silent sound started. Next alarm: \(alarmTime?.formatted() ?? "nil")")

        // 알람 등록은 플랫폼에 위임. (iOS 26은 AlarmKit weekly alarm 등록, iOS 18은 없음)
        // Silent audio loop은 유지 — 알람 시간에 시스템 볼륨 오버라이드 위해 앱을 살아있게 함.
        alarmPlatform.scheduleAlarm(hour: hour, minute: minute, weekdays: weekdays)
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

        // 알람용 볼륨 채널 진입은 플랫폼에 위임.
        // (iOS 26은 Ringtone 채널 볼륨을 유저 설정값으로 저장·적용, iOS 18은 미디어 채널만 써서 없음)
        alarmPlatform.applyAlarmVolume(target: targetVolume)

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

        // 울림 순간 처리는 플랫폼에 위임.
        // (iOS 26은 AlarmKit이 알림/사운드 대체 → 발동 기록만, iOS 18은 로컬 노티 1개 + burst 30개)
        alarmPlatform.handleAlarmFired()

        print("🔔 Alarm sound started (target volume: \(Int(targetVolume * 100))%)")
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

    /// 영속화된 알람 울림 상태가 "아직 유효한 복원 대상"인지 판정하는 순수 함수.
    /// 외부 상태(UserDefaults/시계)를 읽지 않아 결정적이고 단위 테스트 가능. 30분 창 경계 검증용.
    /// - Returns: 울리는 중(isRinging)이고 기록(timestamp>0)이 있으며 경과시간이 만료창 미만이면 true.
    static func isAlarmRingingValid(
        isRinging: Bool,
        timestamp: Double,
        now: Double,
        maxDurationSec: TimeInterval
    ) -> Bool {
        guard isRinging, timestamp > 0 else { return false }
        return (now - timestamp) < maxDurationSec
    }

    /// 강제 종료 후 재실행 시 알람 상태 확인 (30분 이내만 유효).
    /// UserDefaults 읽기만 담당하고 판정은 순수 함수 isAlarmRingingValid에 위임한다.
    static func isAlarmRingingPersisted() -> Bool {
        let ud = UserDefaults(suiteName: appGroupID)
        return isAlarmRingingValid(
            isRinging: ud?.bool(forKey: isAlarmRingingKey) == true,
            timestamp: ud?.double(forKey: alarmRingingTimestampKey) ?? 0,
            now: Date().timeIntervalSince1970,
            maxDurationSec: alarmRingingMaxDurationSec
        )
    }

    /// 영속화된 알람 상태 초기화
    static func clearAlarmRingingPersistence() {
        let ud = UserDefaults(suiteName: appGroupID)
        ud?.set(false, forKey: isAlarmRingingKey)
        ud?.removeObject(forKey: alarmRingingTimestampKey)
        ud?.removeObject(forKey: originalVolumeKey)
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
        // 알람 채널(Ringtone) 볼륨 로드는 플랫폼에 위임. (iOS 18은 없음)
        alarmPlatform.loadPersistedAlarmVolume()
    }

    // MARK: - Volume Restoration Timer
    /// 0.2초 간격으로 무조건 미디어 + Ringtone 볼륨 둘 다 갈김. 현재 볼륨 확인 안 함.
    /// AlarmKit / 시스템이 우리 설정을 덮어쓰는 케이스 대비.
    private func startVolumeRestorationTimer(targetVolume: Float) {
        volumeRestorationTimer?.invalidate()
        volumeRestorationTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self = self, self.isAlarmMode else { return }
            self.setSystemVolume(targetVolume)
            self.alarmPlatform.reinforceAlarmVolume(target: targetVolume)
        }
    }

    private func stopVolumeRestorationTimer() {
        volumeRestorationTimer?.invalidate()
        volumeRestorationTimer = nil
    }

    // MARK: - App Termination Warning (Dead Man's Switch)
    /// internal: 테스트에서 직접 호출해 종료 경고 노티 등록 패턴을 검증한다.
    /// iOS 26+에서 이 경고가 불필요한지 여부는 호출부(checkAlarmTime)가 판단한다.
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
            // iOS 26+는 AlarmKit이 강제 종료 후에도 시스템 레벨에서 울리므로 경고 불필요 (플랫폼이 판단)
            if alarmPlatform.needsTerminationWarning {
                scheduleTerminationWarning()
            }
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

        // 시스템 미디어 볼륨 복원 + 알람 채널(Ringtone) 볼륨 복원은 플랫폼에 위임
        setSystemVolume(originalSystemVolume)
        alarmPlatform.restoreAlarmVolume()
        print("🔄 System volume restored to: \(Int(originalSystemVolume * 100))%")

        // 알람용 fresh AVAudioPlayer 정지 후 silent loop을 재구성 — audio session도
        // mixWithOthers 옵션으로 다시 setup해 다른 앱 오디오와 공존 가능 상태로 복귀.
        audioPlayer?.stop()
        audioPlayer = nil
        setupAudioSession()
        playSilentSound()
        isAlarmMode = false

        // 영속화 상태 초기화 + 지금 울리는 알람만 정지 (주간 반복 예약은 유지)
        // iOS 18은 burst 취소, iOS 26은 AlarmKit alerting/backup 정지 — 플랫폼이 처리.
        persistAlarmRinging(false)
        alarmPlatform.stopAlerting()

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

        // 알람 모드였다면 시스템 미디어 볼륨 + 알람 채널(Ringtone) 볼륨 모두 복원
        if isAlarmMode {
            setSystemVolume(originalSystemVolume)
            print("🔄 System volume restored to: \(Int(originalSystemVolume * 100))%")
            alarmPlatform.restoreAlarmVolume()
        }

        audioPlayer?.stop()
        audioPlayer = nil
        checkTimer?.invalidate()
        checkTimer = nil
        isPlaying = false
        isAlarmMode = false
        alarmTime = nil

        // 영속화 상태 초기화 + 알람 자체 취소 (유저가 알람을 off)
        // iOS 18은 burst 취소, iOS 26은 AlarmKit 알람 전체 취소 + 관찰 종료 — 플랫폼이 처리.
        persistAlarmRinging(false)
        alarmPlatform.cancelAll()

        // 알람 끄면 종료 경고 노티도 취소
        scheduler.removePending(identifiers: ["appTerminationWarning"])

        print("🛑 Background audio player stopped")
    }
}
