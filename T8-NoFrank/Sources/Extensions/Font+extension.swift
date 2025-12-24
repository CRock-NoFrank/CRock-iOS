//
//  Font+extension.swift
//  T8-NoFrank
//
//  Created by 이주현 on 8/7/25.
//

import SwiftUI

enum Pretendard: String {
    case black = "Pretendard-Black"
    case bold = "Pretendard-Bold"
    case extraBold = "Pretendard-ExtraBold"
    case extraLight = "Pretendard-ExtraLight"
    case light = "Pretendard-Light"
    case medium = "Pretendard-Medium"
    case regular = "Pretendard-Regular"
    case semiBold = "Pretendard-SemiBold"
    case thin = "Pretendard-Thin"
}

extension Font {
    static let title01: Font = .custom(Pretendard.semiBold.rawValue, size: 40)
    static let subtitleMedium: Font = .custom(Pretendard.medium.rawValue, size: 19)
    
    static let body01: Font = .custom(Pretendard.regular.rawValue, size: 30)
    static let body01Bold: Font = .custom(Pretendard.bold.rawValue, size: 30)
    
    static let callout01: Font = .custom(Pretendard.regular.rawValue, size: 20)
    
    static let subheadlineMedium: Font = .custom(Pretendard.medium.rawValue, size: 17)
    static let caption1Medium: Font = .custom(Pretendard.medium.rawValue, size: 15)
    
    static let caption1SemiBold: Font = .custom(Pretendard.semiBold.rawValue, size: 15)
    
    static let alarmTime: Font = .custom(Pretendard.bold.rawValue, size: 90)
}
