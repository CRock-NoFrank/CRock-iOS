//
//  C.swift
//  T8-NoFrank
//
//  Created by 이주현 on 8/9/25.
//

import SwiftUI

struct CustomToggle: View {
    @Binding var isOn: Bool
    
    init(isOn: Binding<Bool>) {
        self._isOn = isOn
    }
    
    var body: some View {
        let switchSize = CGSize(width: 52, height: 32)
    
        ZStack(alignment: .top) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(isOn ? .orange1 : .gray1)
                .frame(width: switchSize.width, height: switchSize.height)
        }
    }
}

struct CustomToggleExample: View {
    @State var previewIsOn: Bool = false
    
    var body: some View {
        CustomToggle(isOn: $previewIsOn)
    }
}

#Preview {
    CustomToggleExample()
}
