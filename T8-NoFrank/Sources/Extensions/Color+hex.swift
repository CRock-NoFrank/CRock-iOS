//
//  Color+hex.swift
//  T8-NoFrank
//
//  Created by 이주현 on 8/7/25.
//

import Foundation
import SwiftUI

// 사용 방법: Color(hex: "000000")
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let scanner = Scanner(string: hex)

        if hex.hasPrefix("#") {
            scanner.currentIndex = hex.index(after: hex.startIndex)
        }

        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)

        let r, g, b, a: Double
        if hex.count == 9 {
            // #RRGGBBAA
            r = Double((rgbValue & 0xFF00_0000) >> 24) / 255
            g = Double((rgbValue & 0x00FF_0000) >> 16) / 255
            b = Double((rgbValue & 0x0000_FF00) >> 8) / 255
            a = Double(rgbValue & 0x0000_00FF) / 255
        } else {
            // #RRGGBB
            r = Double((rgbValue & 0xFF0000) >> 16) / 255
            g = Double((rgbValue & 0x00FF00) >> 8) / 255
            b = Double(rgbValue & 0x0000FF) / 255
            a = 1
        }

        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
