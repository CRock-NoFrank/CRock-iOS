//
//  BreakingStoneView.swift
//  T8-NoFrank
//
//  Created by 문창재 on 8/9/25.
//

import SwiftUI

struct BreakingStoneView: View {
    @State private var alarmHour: Int = 0
    @State private var alarmMinute: Int = 0

    var body: some View {
        VStack {
            ZStack {
                Image("Home_Background")
                    .resizable()
                    .scaledToFill()
                    .frame(width: screenWidth, height: screenHeight)
                Text(String(format: "%02d:%02d", alarmHour, alarmMinute))
                    .font(.alarmTime)
                    .foregroundColor(.white)
                    .padding(.bottom, 500)
                Color.black
                    .opacity(0.7)
                    .edgesIgnoringSafeArea(.all)
                MovingRock(isBreakable: true)
            }
        }
        .onAppear {
            if let hour = UserDefaults(suiteName: AppConstants.appGroupID)?
                .object(forKey: "alarmHour") as? Int,
                let minute = UserDefaults(suiteName: AppConstants.appGroupID)?
                    .object(forKey: "alarmMinute") as? Int
            {
                alarmHour = hour
                alarmMinute = minute
            }
        }
    }
}

#Preview {
    BreakingStoneView()
}
