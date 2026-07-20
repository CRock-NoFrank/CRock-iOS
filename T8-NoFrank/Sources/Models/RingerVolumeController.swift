//
//  RingerVolumeController.swift
//  T8-NoFrank
//
//  ⚠️ PRIVATE API USAGE — App Store 리뷰 거절 위험 있음.
//  iOS의 "Ringtone" 볼륨 카테고리(= 벨소리/알람 채널)를 직접 set/get하기 위해
//  Celestial.framework의 AVSystemController를 dynamic dispatch로 호출.
//
//  AlarmKit는 시스템 Ringtone 채널을 통해 사운드를 출력하는데, 공식 API로는
//  이 채널의 볼륨을 조작할 수 없음. AlarmKit alerting 중에도 우리가 직접 ringer
//  볼륨을 유저 설정값으로 강제하기 위해 이 우회를 사용함.
//
//  Reference: blog.alanyip.me/ios-volume (archive), Celestial.framework headers.
//

import Foundation

enum RingerVolumeCategory: String {
    case ringtone = "Ringtone"
    case ringtonePreview = "RingtonePreview"
    case audioVideo = "Audio/Video"
}

final class RingerVolumeController {
    static let shared = RingerVolumeController()
    private init() {}

    /// AVSystemController.sharedAVSystemController instance를 dynamic 호출로 획득.
    private var systemController: NSObject? {
        guard let cls = NSClassFromString("AVSystemController") as? NSObject.Type else {
            return nil
        }
        let selector = NSSelectorFromString("sharedAVSystemController")
        guard cls.responds(to: selector) else { return nil }
        return cls.perform(selector)?.takeUnretainedValue() as? NSObject
    }

    /// 지정 카테고리의 현재 볼륨을 읽음. 실패 시 nil.
    func getVolume(for category: RingerVolumeCategory = .ringtone) -> Float? {
        guard let controller = systemController else { return nil }
        let selector = NSSelectorFromString("getVolume:forCategory:")
        guard controller.responds(to: selector) else { return nil }

        let imp = controller.method(for: selector)
        typealias Signature = @convention(c) (NSObject, Selector, UnsafeMutablePointer<Float>, NSString) -> Bool
        let fn = unsafeBitCast(imp, to: Signature.self)

        var volume: Float = 0
        let ok = fn(controller, selector, &volume, category.rawValue as NSString)
        return ok ? volume : nil
    }

    /// 지정 카테고리의 볼륨을 강제 설정. 실패 시 false.
    @discardableResult
    func setVolume(_ volume: Float, for category: RingerVolumeCategory = .ringtone) -> Bool {
        guard let controller = systemController else { return false }
        let selector = NSSelectorFromString("setVolumeTo:forCategory:")
        guard controller.responds(to: selector) else { return false }

        let imp = controller.method(for: selector)
        typealias Signature = @convention(c) (NSObject, Selector, Float, NSString) -> Bool
        let fn = unsafeBitCast(imp, to: Signature.self)

        let clamped = min(max(volume, 0.0), 1.0)
        return fn(controller, selector, clamped, category.rawValue as NSString)
    }
}
