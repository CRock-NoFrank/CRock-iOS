//
//  AppRouter.swift
//  T8-NoFrank
//
//  Created by 이주현 on 8/7/25.
//

import Foundation
import SwiftUI

enum AppScreen {
    case home
    case breakingStone
    case stonedust
}

@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    @Published private(set) var currentScreen: AppScreen = .home

    func navigate(_ screen: AppScreen) {
        currentScreen = screen
    }
}
