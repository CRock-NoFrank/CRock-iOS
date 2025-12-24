//
//  View+.swift
//  T8-NoFrank
//
//  Created by Sean Cho on 8/15/25.
//


import SwiftUI

extension View {
    /// 디바이스의 스크린 너비
    var screenWidth: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .screen
            .bounds.width) ?? 0
    }

    /// 디바이스의 스크린 높이
    var screenHeight: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .screen
            .bounds.height) ?? 0
    }
}
