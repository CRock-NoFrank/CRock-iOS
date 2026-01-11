//
//  MovingRockScene.swift
//  T8-NoFrank
//
//  Created by SeanCho on 8/8/25.
//

import SpriteKit
import SwiftUI

class RockScene: SKScene {
    var rockPhase: Int = 0 {
        didSet { updateRockTexture(updatePhysics: true) }
    }
    var isRockPain: Bool = false {
        didSet { updateRockTexture(updatePhysics: false) }
    }

    private let rockNode = SKSpriteNode()
    private var currentRockSize: CGSize = .zero

    var tiltAcceleration: CGVector = .zero
    var isShaking: Bool = false

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        physicsWorld.gravity = .zero

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

        if !frame.contains(rockNode.position) {
            rockNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        }
    }

    func updateRockTexture(updatePhysics: Bool) {
        let imageName = "Rock\(rockPhase)\(isRockPain ? "pain" : "")"
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

        let body = SKPhysicsBody(texture: texture, size: rockNode.size)

        body.allowsRotation = true
        body.linearDamping = 3.0
        body.angularDamping = 2.0
        body.restitution = 0.35
        body.friction = 0.2
        body.mass = 1.0
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
        }
    }
}

struct MovingRockSpriteView: View {
    @State var isBreakable: Bool
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
            .opacity(isSceneReady ? 1 : 0)
            .onAppear {
                sceneWrapper.scene.rockPhase = rockPhase
                sceneWrapper.scene.isRockPain = isRockPain

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation {
                        isSceneReady = true
                    }
                }
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

        let selectedTime: Date = {
            var comps = Calendar.current.dateComponents(
                [.hour, .minute],
                from: Date()
            )
            comps.hour = UserDefaults.standard.integer(forKey: "alarmHour")
            comps.minute = UserDefaults.standard.integer(forKey: "alarmMinute")
            return Calendar.current.date(from: comps) ?? Date()
        }()

        let comps = Calendar.current.dateComponents(
            [.hour, .minute, .second],
            from: selectedTime
        )
        let h = comps.hour ?? 0
        let m = comps.minute ?? 0
        let s = comps.second ?? 0

        for i in 0..<8 {
            var sec: Int { s + (i * 30) }
            var min: Int { sec / 60 + m }
            var hour: Int { min / 60 + h }
            NotificationService.cancelTodayBurst(
                hour: h % 24,
                minute: min % 60,
                second: sec % 60,
                totalCount: 8,
                baseKey: "WEEKLY_BURST"
            )
        }

        AppRouter.shared.navigate(.blowAwayStone)
    }
}
