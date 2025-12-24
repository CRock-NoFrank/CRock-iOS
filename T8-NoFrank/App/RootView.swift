//
//  RootView.swift
//  T8-NoFrank
//
//  Created by Sean Cho on 12/25/25.
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject var router: AppRouter

    var body: some View {
        Group {
            switch router.currentScreen {
            case .home: HomeView()
            case .breakingStone: BreakingStoneView()
            case .stonedust: StoneDustView()
            }
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AppRouter())
}
