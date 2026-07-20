//
//  BlowDetection.swift
//  T8-NoFrank
//
//  Created by JiJooMaeng on 8/8/25.
//

import AVFoundation
import Accelerate
import Foundation

@Observable
final class BlowDetector {
    private var audioEngine: AVAudioEngine?
    private var currentStageBlowTime: Double = 0.0

    var blowStage: Int = 0

    private let fftSize = 2048
    private var fftSetup: FFTSetup?

    init() {
        // log2(2048) = 11
        fftSetup = vDSP_create_fftsetup(11, FFTRadix(kFFTRadix2))
    }

    deinit {
        if let setup = fftSetup {
            vDSP_destroy_fftsetup(setup)
        }
    }

    func start() {
        stop()
        blowStage = 0
        currentStageBlowTime = 0.0

        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord,
                mode: .default,
                options: []
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("설정 실패: \(error)")
            return
        }

        let engine = AVAudioEngine()
        audioEngine = engine

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        let sampleRate = format.sampleRate

        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(fftSize), format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let isBlow = self.isBlowSound(buffer: buffer, sampleRate: sampleRate)
            let frameDuration = Double(buffer.frameLength) / sampleRate

            DispatchQueue.main.async {
                self.updateStage(isBlow: isBlow, duration: frameDuration)
            }
        }

        do {
            try engine.start()
        } catch {
            print("오류: \(error.localizedDescription)")
        }
    }

    // 바람 vs 음성 구별 전략: Spectral Flatness Measure (SFM)
    // - 바람: 잡음성 → 스펙트럼이 평탄 → SFM 높음 (0.05~0.3)
    // - 음성("아~"): 기본음+배음이 특정 주파수에만 집중 → SFM 낮음 (0.001~0.01)
    private func isBlowSound(buffer: AVAudioPCMBuffer, sampleRate: Double) -> Bool {
        guard let channelData = buffer.floatChannelData?[0],
              let fftSetup else { return false }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return false }

        // RMS 진폭 체크
        var rms: Float = 0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameCount))
        guard rms > 0.01 else { return false }

        // 샘플 복사 + Hann 윈도우
        var samples = [Float](repeating: 0, count: fftSize)
        let copyCount = min(frameCount, fftSize)
        for i in 0..<copyCount { samples[i] = channelData[i] }

        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(samples, 1, window, 1, &samples, 1, vDSP_Length(fftSize))

        // FFT → 파워 스펙트럼
        var real = [Float](repeating: 0, count: fftSize / 2)
        var imag = [Float](repeating: 0, count: fftSize / 2)
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)

        real.withUnsafeMutableBufferPointer { realBuf in
            imag.withUnsafeMutableBufferPointer { imagBuf in
                var split = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                samples.withUnsafeBytes { rawPtr in
                    vDSP_ctoz(
                        rawPtr.baseAddress!.assumingMemoryBound(to: DSPComplex.self),
                        2, &split, 1, vDSP_Length(fftSize / 2)
                    )
                }
                vDSP_fft_zrip(fftSetup, &split, 1, vDSP_Length(11), FFTDirection(FFT_FORWARD))
                magnitudes.withUnsafeMutableBufferPointer { magBuf in
                    vDSP_zvmags(&split, 1, magBuf.baseAddress!, 1, vDSP_Length(fftSize / 2))
                }
            }
        }

        // SFM = 기하평균 / 산술평균
        // 평탄한 스펙트럼(바람) → 1에 가까움, 뾰족한 스펙트럼(음성) → 0에 가까움
        let binCount = fftSize / 2
        var arithMean: Float = 0
        vDSP_meanv(magnitudes, 1, &arithMean, vDSP_Length(binCount))
        guard arithMean > 0 else { return false }

        let eps = arithMean * 1e-3 // log(0) 방지용 상대적 epsilon
        var logSum: Float = 0
        for mag in magnitudes {
            logSum += log(mag + eps)
        }
        let sfm = exp(logSum / Float(binCount)) / arithMean

        // print("RMS: \(rms), SFM: \(sfm)") // 값 확인 시 주석 해제
        return sfm > 0.03
    }

    private func updateStage(isBlow: Bool, duration: Double) {
        if isBlow {
            currentStageBlowTime += duration

            if blowStage == 0 && currentStageBlowTime >= 1.5 {
                blowStage = 1
                currentStageBlowTime = 0.0
            } else if blowStage == 1 && currentStageBlowTime >= 1.5 {
                blowStage = 2
                currentStageBlowTime = 0.0
            } else if blowStage == 2 && currentStageBlowTime >= 1.5 {
                blowStage = 3
                currentStageBlowTime = 0.0
            }
        } else {
            currentStageBlowTime = 0.0
        }
    }

    func stop() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}
