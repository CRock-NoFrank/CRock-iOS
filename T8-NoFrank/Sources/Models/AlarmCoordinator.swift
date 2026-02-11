//
//  AlarmCoordinator.swift
//  T8-NoFrank
//
//  Created by JiJooMaeng on 2/10/26.
//
//  iOS 26 AlarmKit과 기존 로컬 노티를 분기 처리하는 코디네이터

import AVFoundation
import Foundation

final class AlarmCoordinator {
    static let shared = AlarmCoordinator()

    /// iOS 26+에서 AlarmKit 사용 가능 여부
    var isAlarmKitAvailable: Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    private init() {
        observeAudioInterruption()
    }

    // MARK: - 알람 스케줄 (다음 알람 시간이 정해졌을 때 호출)
    func scheduleNextAlarm(date: Date) {
        AlarmKitAvailability.scheduleAlarmIfAvailable(date: date)
    }

    // MARK: - 알람 취소
    func cancelAlarm() {
        AlarmKitAvailability.cancelAlarmIfAvailable()
    }

    // MARK: - 오디오 세션 복원 (AlarmKit이 오디오 세션을 가져간 뒤 복원)
    func recoverAudioSession() {
        Task { // Make it async to allow for potential delay and better error handling
            do {
                let session = AVAudioSession.sharedInstance()
                
                // Deactivate the session first to clear any previous state
                try? session.setActive(false, options: .notifyOthersOnDeactivation) // Try to deactivate, ignore if already inactive

                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                
                // Keep the delay as it might still help with timing
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second delay
                
                try session.setActive(true)
                print("🔄 AlarmCoordinator에 의해 오디오 세션이 복구되었습니다.") // Re-adding this print
            } catch {
                print("❌ 오디오 세션 복구 실패: \(error)") // Updated to include X
            }
        }
    }

    // MARK: - Audio Interruption Observer (AlarmKit 해제 시 자동 복원)
    private func observeAudioInterruption() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

            if type == .ended {
                self.recoverAudioSession()
                let player = BackgroundAudioPlayer.shared
                player.resumeAfterInterruption()
            }
        }
    }
}
