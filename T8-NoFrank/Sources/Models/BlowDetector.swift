//
//  BlowDetection.swift
//  T8-NoFrank
//
//  Created by JiJooMaeng on 8/8/25.
//

import AVFoundation
import Foundation

@Observable
final class BlowDetector {
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var currentStageBlowTime: Double = 0.0

    var blowStage: Int = 0

    func start() {
        stop()

        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord,
                mode: .default,
                options: []
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("설정 실패: \(error)")
        }

        let url = URL(fileURLWithPath: "/dev/null")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatAppleLossless),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
        ]

        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
            if let recorder = recorder {
                recorder.isMeteringEnabled = true
                _ = recorder.record()
                timer = Timer.scheduledTimer(
                    withTimeInterval: 0.1,
                    repeats: true
                ) { [weak self] _ in
                    guard let self, let recorder = self.recorder else { return }
                    recorder.updateMeters()
                    let db = recorder.peakPower(forChannel: 0)
                    //                    print("실시간 데시벨: \(db)")
                    if db > -10 {
                        self.currentStageBlowTime += 0.1

                        if self.blowStage == 0
                            && self.currentStageBlowTime >= 1.5
                        {
                            self.blowStage = 1
                            self.currentStageBlowTime = 0.0
                        } else if self.blowStage == 1
                            && self.currentStageBlowTime >= 1.5
                        {
                            self.blowStage = 2
                            self.currentStageBlowTime = 0.0
                        } else if self.blowStage == 2
                            && self.currentStageBlowTime >= 1.5
                        {
                            self.blowStage = 3
                            self.currentStageBlowTime = 0.0
                        }
                    } else {
                        self.currentStageBlowTime = 0.0
                    }
                }
            }
        } catch {
            print("오류: \(error.localizedDescription)")
        }
    }

    func stop() {
        timer?.invalidate()
        recorder?.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}
