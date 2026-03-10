//
//  MovingRockScene.swift
//  T8-NoFrank
//
//  Created by SeanCho on 8/8/25.
//

import SpriteKit
import SwiftUI

class RockScene: SKScene, SKPhysicsContactDelegate {
    var rockPhase: Int = 0 {
        didSet { updateRockTexture(updatePhysics: true) }
    }
    var isRockPain: Bool = false {
        didSet { updateRockTexture(updatePhysics: false) }
    }
    var weekdayPrefix: String? = nil {
        didSet { updateRockTexture(updatePhysics: true) }
    }

    private let rockNode = SKSpriteNode()
    private var currentRockSize: CGSize = .zero

    var tiltAcceleration: CGVector = .zero
    var isShaking: Bool = false

    // 벽 슬라이딩 햅틱 (드르르륵 진동)
    private var lastWallHapticTime: TimeInterval = 0
    private let wallHapticInterval: TimeInterval = 0.06
    private let wallHapticGenerator = UIImpactFeedbackGenerator(style: .soft)
    private var isContactingWall: Bool = false

    // 물리 충돌 카테고리
    private let rockCategory: UInt32 = 0x1 << 0
    private let wallCategory: UInt32 = 0x1 << 1

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self
        wallHapticGenerator.prepare()

        // Setup Rock
        updateRockTexture(updatePhysics: true)
        rockNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(rockNode)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        physicsBody = SKPhysicsBody(edgeLoopFrom: frame)
        physicsBody?.friction = 0
        physicsBody?.restitution = 0.35
        physicsBody?.categoryBitMask = wallCategory
        physicsBody?.contactTestBitMask = rockCategory

        if !frame.contains(rockNode.position) {
            rockNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        }
    }

    func updateRockTexture(updatePhysics: Bool) {
        let imageName: String
        if let prefix = weekdayPrefix {
            imageName = "\(prefix)/\(rockPhase)Stage\(isRockPain ? "_Bright" : "")"
        } else {
            imageName = "Rock\(rockPhase)\(isRockPain ? "pain" : "")"
        }
        let texture = SKTexture(imageNamed: imageName)
        rockNode.texture = texture

        if updatePhysics {
            rockNode.size = texture.size()
            currentRockSize = texture.size()

            setupPhysicsBody()
        }
    }

    private func setupPhysicsBody() {
        guard let texture = rockNode.texture else { return }

        // 오뚜기 효과: anchorPoint를 아래쪽으로 이동 (회전 중심이 아래로 내려감)
        rockNode.anchorPoint = CGPoint(x: 0.5, y: 0.3)
        
        let body = SKPhysicsBody(texture: texture, size: rockNode.size)

        body.allowsRotation = true
        body.linearDamping = 3.0
        body.angularDamping = 2.0
        body.restitution = 0.35
        body.friction = 0.2
        body.mass = 1.0
        body.categoryBitMask = rockCategory
        body.contactTestBitMask = wallCategory
        
        rockNode.physicsBody = body
    }

    private func getRockSize(phase: Int) -> (CGFloat, CGFloat) {
        return (0, 0)
    }

    func applyShake(vector: CGVector) {
        guard let body = rockNode.physicsBody else { return }

        let speed: CGFloat = 2500.0
        body.velocity = CGVector(dx: vector.dx * speed, dy: vector.dy * speed)

        let randomSpin = CGFloat.random(in: -5...5)
        body.angularVelocity = randomSpin
    }

    override func update(_ currentTime: TimeInterval) {
        if !isShaking, let body = rockNode.physicsBody {
            let accelPerG: CGFloat = 2000.0
            let force = CGVector(
                dx: tiltAcceleration.dx * accelPerG,
                dy: tiltAcceleration.dy * accelPerG
            )
            body.applyForce(force)
            
            // 오뚜기 효과: 회전 복원력 추가
            // 현재 회전 각도를 0도로 되돌리려는 토크
            let currentAngle = rockNode.zRotation
            let restoreTorque: CGFloat = -currentAngle * 10.0 // 복원력 강도
            let dampingTorque: CGFloat = -body.angularVelocity * 3.0 // 감쇠력
            body.applyTorque(restoreTorque + dampingTorque)
        }

        // 벽에 닿으면서 움직일 때 드르르륵 햅틱
        checkWallSliding(currentTime)
    }

    // MARK: - SKPhysicsContactDelegate

    func didBegin(_ contact: SKPhysicsContact) {
        let masks = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        if masks == (rockCategory | wallCategory) {
            isContactingWall = true
        }
    }

    func didEnd(_ contact: SKPhysicsContact) {
        let masks = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        if masks == (rockCategory | wallCategory) {
            isContactingWall = false
        }
    }

    /// 돌이 벽에 닿아 있으면서 속도가 있으면 약한 햅틱 반복 발생
    private func checkWallSliding(_ currentTime: TimeInterval) {
        guard isContactingWall else { return }
        guard let body = rockNode.physicsBody else { return }

        let speed = hypot(body.velocity.dx, body.velocity.dy)
        guard speed > 5 else { return } // 너무 느리면 무시
        guard currentTime - lastWallHapticTime >= wallHapticInterval else { return }

        lastWallHapticTime = currentTime
        let intensity = min(speed / 400.0, 1.0)
        wallHapticGenerator.impactOccurred(intensity: intensity)
    }
}

struct MovingRockSpriteView: View {
    @State var isBreakable: Bool
    var weekday: Weekday? = nil
    @State var isClockEnd: Bool = false

    @StateObject private var sceneWrapper = SceneWrapper()

    private let shakeManager = MotionManager()

    @State private var rockPhase: Int = 0
    @State private var rockPhaseCount: Int = 0
    @State private var isRockPain: Bool = false
    @State private var isShaking: Bool = false
    @State private var isSceneReady: Bool = false

    @State private var shakeTask: Task<Void, Never>? = nil
    @State private var tiltTask: Task<Void, Never>? = nil

    class SceneWrapper: ObservableObject {
        let scene: RockScene

        init() {
            let scene = RockScene()
            scene.scaleMode = .resizeFill
            self.scene = scene
        }
    }

    var body: some View {
        ZStack {
            SpriteView(
                scene: sceneWrapper.scene,
                options: [.allowsTransparency]
            )
            .background(Color.clear)
            .padding(.horizontal, isBreakable ? 0 : 20)
            .padding(.top, isBreakable ? 0 : 60)
            .opacity(isSceneReady ? 1 : 0)
            .onAppear {
                sceneWrapper.scene.weekdayPrefix = weekday?.assetPrefix
                sceneWrapper.scene.rockPhase = rockPhase
                sceneWrapper.scene.isRockPain = isRockPain

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation {
                        isSceneReady = true
                    }
                }
            }
            .onChange(of: weekday) { newValue in
                sceneWrapper.scene.weekdayPrefix = newValue?.assetPrefix
            }
            .onChange(of: rockPhase) { newValue in
                sceneWrapper.scene.rockPhase = newValue
            }
            .onChange(of: isRockPain) { newValue in
                sceneWrapper.scene.isRockPain = newValue
            }
            .onChange(of: isShaking) { newValue in
                sceneWrapper.scene.isShaking = newValue
            }
        }
        .overlay {
            ZStack {
                Image("DustLayer1").resizable().scaledToFill().opacity(
                    rockPhase > 0 ? 1 : 0
                )
                Image("DustLayer2").resizable().scaledToFill().opacity(
                    rockPhase > 2 ? 1 : 0
                )
                Image("DustLayer3").resizable().scaledToFill().opacity(
                    rockPhase > 4 ? 1 : 0
                )
            }
            .onAppear { isClockEnd.toggle() }
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            shakeManager.start()

            shakeTask = Task {
                for await deg in shakeManager.shakeDegreesStream {
                    await handleShakeDegree(deg)
                }
            }

            tiltTask = Task {
                for await vec in shakeManager.tiltUnitStream {
                    await handleTiltVector(vec)
                }
            }
        }
        .onDisappear {
            shakeManager.stopAll()
            shakeTask?.cancel()
            tiltTask?.cancel()
        }
    }

    private func handleShakeDegree(_ deg: Int) async {
        if isBreakable { isRockPain = true }

        Task {
            try? await Task.sleep(for: .seconds(0.1))
            isRockPain = false
        }

        isShaking = true

        let theta = CGFloat(Double(deg) * .pi / 180)
        let ux = sin(theta)
        let uy = -cos(theta)
        let vector = CGVector(dx: ux, dy: -uy)

        sceneWrapper.scene.applyShake(vector: vector)

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        try? await Task.sleep(for: .seconds(0.1))

        if isBreakable {
            rockPhaseCount += 1
            if rockPhaseCount > 20 {
                if rockPhase == 4 {
                    handleBreakComplete()
                } else {
                    rockPhase += 1
                    rockPhaseCount = 0
                }
            }
        }

        isShaking = false
    }

    private func handleTiltVector(_ vec: CGVector) async {
        let deadzone: CGFloat = 0.02
        let ux = abs(vec.dx) < deadzone ? 0 : CGFloat(vec.dx)
        let uy = abs(vec.dy) < deadzone ? 0 : CGFloat(vec.dy)

        let targetUy = -uy

        let smoothing: CGFloat = 0.15
        let current = sceneWrapper.scene.tiltAcceleration
        let newX = current.dx * (1 - smoothing) + ux * smoothing
        let newY = current.dy * (1 - smoothing) + targetUy * smoothing

        sceneWrapper.scene.tiltAcceleration = CGVector(dx: newX, dy: newY)
    }

    private func handleBreakComplete() {
        rockPhase = 0
        rockPhaseCount = 0

        BackgroundAudioPlayer.shared.stopAlarmAndBackToSilent()

        AppRouter.shared.navigate(.blowAwayStone)
    }
}
