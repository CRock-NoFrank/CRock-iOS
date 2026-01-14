//
//  WeekdayToggleButton.swift
//  T8-NoFrank
//
//  Created by 나현흠 on 8/9/25.
//

import SwiftUI

struct WeekdayToggleButton: View {
    let title: String
    @Binding var isSelected: Bool

    var body: some View {
        Button(action: {
            isSelected.toggle()
        }) {
            Text(title)
                .font(.custom("Pretendard", size: 15))
                .foregroundStyle(Color.white)
        }
        .frame(width: 40, height: 40)
        .background(Circle().fill(isSelected ? .orange2 : .gray2))
    }
}
