//
//  BlowAwayStoneView.swift
//  T8-NoFrank
//
//  Created by JiJooMaeng on 8/8/25.
//

import SwiftUI


struct BlowAwayStoneView: View {
    @State private var blowDetector = BlowDetector()
    
    @State private var triggerActivated = false
    @State private var dustOffset: CGFloat = 0
    @State private var newStoneOffset: CGFloat = 400
    @State private var newStoneOpacity: Double = 0
    @State private var a2Offset: CGFloat = 0
    @State private var b2Offset: CGFloat = 0
    
    var body: some View {
        ZStack {
            Image("Home_Background")
            Color.black
                .opacity(0.7)
                .edgesIgnoringSafeArea(.all)
            VStack {
                    if !triggerActivated {
                        Text("돌이 깨졌어요")
                            .font(.body01Bold)
                            .foregroundStyle(.white)
                            .padding(.top, 139)
                    }
                    Spacer()
                }
            
            ZStack {
                VStack {
                    Group {
                        if blowDetector.blowStage == 0 {
                            Image("stoneDust")
                        } else if blowDetector.blowStage == 1 {
                            Image("stoneDustA1")
                            Image("stoneDustA2")
                                .offset(x: a2Offset * 2 - 20, y: a2Offset * 2 - 100)
                                .opacity(1.0 - min(1.0, Double(abs(a2Offset / 100))))
                        } else if blowDetector.blowStage == 2 {
                            Image("stoneDustB1")
                            Image("stoneDustB2")
                                .offset(x: -b2Offset * 2 - 60, y: b2Offset * 2 - 100)
                                .opacity(1.0 - min(1.0, Double(abs(b2Offset / 100))))
                        } else if blowDetector.blowStage == 3 {
                            Image("stoneDustB1")
                                .offset(x: dustOffset)
                                .opacity(1.0 - min(1.0, Double(abs(dustOffset / 300))))
                        }
                    }
                    Spacer()
                }
                .padding(.top, 426)
                VStack {
                    Image("RockDefault")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 189, height: 230)
                        .rotationEffect(.degrees(newStoneOffset == 0 ? 0 : 720))
                        .offset(x: newStoneOffset)
                        .opacity(newStoneOpacity)
                    Spacer()
                }
                .padding(.top, 359)
            }
        }
        .onChange(of: blowDetector.blowStage) { _, stage in
            switch stage {
            case 1:
                withAnimation(.easeOut(duration: 1.5)) {
                    a2Offset = -200
                }
            case 2:
                withAnimation(.easeOut(duration: 1.5)) {
                    b2Offset = -300
                }
            case 3:
                Task {
                    withAnimation(.easeOut(duration: 2)) {
                        dustOffset = -400
                        newStoneOffset = 0
                        newStoneOpacity = 1
                        triggerActivated = true
                    }
                    blowDetector.stop()
                    
                    try? await Task.sleep(for: .seconds(2))
                    AppRouter.shared.navigate(.home)
                }
            default:
                break
            }
        }
        .onDisappear {
            blowDetector.stop()
        }
        .onAppear {
            triggerActivated = false
            dustOffset = 0
            newStoneOffset = 400
            newStoneOpacity = 0
            a2Offset = 0
            b2Offset = 0
            blowDetector.start()
        }
    }
}

#Preview {
    BlowAwayStoneView()
}
