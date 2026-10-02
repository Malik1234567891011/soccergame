import SceneKit
import SpriteKit
import PannaCore

struct RenderPlayerInfo {
    var appearance: Appearance
    var celebration: Int
    var name: String
    var model: String? = nil
}

/// Turns sim state into a living SceneKit scene. Never mutates the sim.
final class MatchRenderer {
    let scene = SCNScene()
    let theme: ArenaTheme
    let arena: ArenaBuilder
    let shape: ArenaShape
    var rigs: [CharacterRig] = []
    var playerNodes: [SCNNode] = []
    var rings: [SCNNode] = []
    let ballNode = SCNNode()
    let exposureRing = SCNNode()
    let ballVisual = SCNNode()
    let ballShadow = SCNNode()
    let landingMarker = SCNNode()
    let cameraNode = SCNNode()
    let camera = SCNCamera()
    let humanArrow = SCNNode()
    var auras: [SCNParticleSystem?] = Array(repeating: nil, count: 8)
    var readyRings: [SCNNode] = []
    let trail: SCNParticleSystem
    let aimArrow = SCNNode()
    let passMarker = SCNNode()
    let teamColors: [UIColor]
    let humanId: Int
    var localHumans: Set<Int>
    let infos: [RenderPlayerInfo]

    // Camera state
    var camTarget = SIMD3<Float>(0, 0, 0)
    var camVel = SIMD3<Float>(0, 0, 0)
    var trauma: Float = 0
    var fovPunch: Float = 0
    var time: Float = 0
    var flowGrade: Float = 0
    var slowmoGrade: Float = 0
    var celebrationCam: Float = 0
    var focusPlayer = -1

    let keeperColors: [UInt32]

    init(theme: ArenaTheme, players: [RenderPlayerInfo], keeperColors: [UInt32] = [0xE8FF3B, 0xFF8A3B], teamColors: [UIColor], humanId: Int, localHumans: Set<Int>, shape: ArenaShape = .standard) {
        self.keeperColors = keeperColors
        self.theme = theme
        self.shape = shape
        self.teamColors = teamColors
        self.humanId = humanId
        self.localHumans = localHumans
        self.infos = players
        arena = ArenaBuilder(theme: theme, shape: shape)
        trail = FX.trail(color: UIColor(hex: players[max(0, humanId)].appearance.trail))
        arena.build(into: scene)
        buildPlayers(players)
        buildBall()
        buildCamera()
    }

    private func buildPlayers(_ players: [RenderPlayerInfo]) {
        for i in 0..<8 {
            let info = players[i]
            let keeper = i % 4 == 3
            let ink = teamColors[i / 4].mixed(with: UIColor(red: 0.05, green: 0.03, blue: 0.08, alpha: 1), 0.55)
            let rig = CharacterRig(appearance: info.appearance, isKeeper: keeper, keeperColor: keeperColors[i / 4], name: info.name,
                                   modelName: info.model, outlineColor: ink)
            let holder = SCNNode()
            holder.addChildNode(rig.root)
            scene.rootNode.addChildNode(holder)
            rigs.append(rig)
            playerNodes.append(holder)
            // Soft blob shadow (cheaper and cleaner than a shadow map from the broadcast angle).
            let blob = SCNPlane(width: 1.1, height: 1.1)
            let bm = SCNMaterial()
            bm.lightingModel = .constant
            bm.diffuse.contents = MatchRenderer.blobImage
            bm.writesToDepthBuffer = false
            bm.transparency = 0.55
            blob.materials = [bm]
            let bn = SCNNode(geometry: blob)
            bn.eulerAngles.x = -.pi / 2
            bn.position.y = 0.012
            bn.castsShadow = false
            holder.addChildNode(bn)
            rig.root.enumerateHierarchy { n, _ in n.castsShadow = false }
            // Team ring.
            let col = teamColors[i / 4]
            let isLocal = localHumans.contains(i)
            let ring = Geo.node(Geo.ring(inner: isLocal ? 0.5 : 0.46, outer: isLocal ? 0.66 : 0.56), Mat.emissive(col, intensity: isLocal ? 2.2 : 0.9))
            ring.position.y = 0.02
            ring.castsShadow = false
            holder.addChildNode(ring)
            rings.append(ring)
            // Flow-ready ring.
            let rr = Geo.node(Geo.ring(inner: 0.72, outer: 0.8), Mat.emissive(UIColor(hex: 0xFFD23B), intensity: 2.5))
            rr.position.y = 0.025
            rr.isHidden = true
            rr.castsShadow = false
            holder.addChildNode(rr)
            readyRings.append(rr)
        }
        // Human marker: floating chevron.
        let cone = SCNCone(topRadius: 0, bottomRadius: 0.16, height: 0.26)
        cone.materials = [Mat.emissive(UIColor(hex: 0xFFFFFF), intensity: 1.6)]
        humanArrow.geometry = cone
        humanArrow.eulerAngles.x = .pi
        humanArrow.castsShadow = false
        scene.rootNode.addChildNode(humanArrow)
        humanArrow.isHidden = humanId < 0
        // Aim arrow.
        let arrow = SCNBox(width: 0.12, height: 0.01, length: 1, chamferRadius: 0)
        arrow.materials = [Mat.emissive(UIColor(white: 1, alpha: 0.8), intensity: 1.5)]
        let an = SCNNode(geometry: arrow)
        an.position = SCNVector3(0, 0, 0.5)
        aimArrow.addChildNode(an)
        let head = SCNCone(topRadius: 0, bottomRadius: 0.2, height: 0.35)
        head.materials = arrow.materials
        let hn = SCNNode(geometry: head)
        hn.eulerAngles.x = .pi / 2
        hn.position = SCNVector3(0, 0, 1.1)
        aimArrow.addChildNode(hn)
        aimArrow.isHidden = true
        aimArrow.castsShadow = false
        scene.rootNode.addChildNode(aimArrow)
        let pm = SCNCone(topRadius: 0, bottomRadius: 0.14, height: 0.22)
        pm.materials = [Mat.emissive(UIColor(hex: 0x39FF88), intensity: 2)]
        passMarker.geometry = pm
        passMarker.eulerAngles.x = .pi
        passMarker.isHidden = true
        passMarker.castsShadow = false
        scene.rootNode.addChildNode(passMarker)
    }

    static let blobImage: UIImage = Tex.render(CGSize(width: 64, height: 64), key: "blob") { c, _ in
        let cs = CGColorSpaceCreateDeviceRGB()
        let g = CGGradient(colorsSpace: cs, colors: [UIColor(white: 0, alpha: 0.8).cgColor, UIColor(white: 0, alpha: 0).cgColor] as CFArray, locations: [0, 1])!
        c.drawRadialGradient(g, startCenter: CGPoint(x: 32, y: 32), startRadius: 0, endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
    }

    static let ballTexture: UIImage = Tex.render(CGSize(width: 512, height: 256), key: "ball") { c, s in
        c.setFillColor(UIColor(white: 0.97, alpha: 1).cgColor); c.fill(CGRect(origin: .zero, size: s))
        // Bold street-ball panels.
        let cols: [UInt32] = [0x111318, 0xFF3B5C, 0x111318, 0x39FF88]
        for i in 0..<8 {
            let x = CGFloat(i) * 64 + 16
            c.setFillColor(UIColor(hex: cols[i % cols.count]).cgColor)
            let y: CGFloat = i % 2 == 0 ? 50 : 150
            let p = UIBezierPath()
            for k in 0..<5 {
                let a = CGFloat(k) / 5 * 2 * .pi - .pi / 2
                let pt = CGPoint(x: x + 16 + cos(a) * 22, y: y + sin(a) * 22)
                if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.close()
            c.addPath(p.cgPath); c.fillPath()
        }
        c.setStrokeColor(UIColor(white: 0.3, alpha: 0.6).cgColor)
        c.setLineWidth(2)
        for y in stride(from: 0, to: 256, by: 64) { c.move(to: CGPoint(x: 0, y: y)); c.addLine(to: CGPoint(x: 512, y: y)) }
        c.strokePath()
    }

    private func buildBall() {
        let r = CGFloat(BallState.radius) * 1.7
        let sphere = SCNSphere(radius: r)
        sphere.segmentCount = 32
        let m = Mat.pbr(.white, rough: 0.35, rim: 0.7, rimColor: UIColor(white: 1, alpha: 1))
        m.diffuse.contents = MatchRenderer.ballTexture
        sphere.materials = [m]
        ballVisual.geometry = sphere
        ballVisual.castsShadow = true
        ballNode.addChildNode(ballVisual)
        ballNode.addParticleSystem(trail)
        scene.rootNode.addChildNode(ballNode)
        let er = SCNPlane(width: 0.9, height: 0.9)
        let erm = SCNMaterial(); erm.diffuse.contents = FX.ring; erm.multiply.contents = UIColor(hex: 0xFF8A3B)
        erm.lightingModel = .constant; erm.blendMode = .add; erm.writesToDepthBuffer = false; erm.isDoubleSided = true
        er.materials = [erm]
        exposureRing.geometry = er
        exposureRing.eulerAngles.x = -.pi / 2
        exposureRing.opacity = 0
        scene.rootNode.addChildNode(exposureRing)
        // Blob shadow — essential for reading ball height.
        let sh = SCNPlane(width: 0.7, height: 0.7)
        let sm = SCNMaterial()
        sm.lightingModel = .constant
        sm.diffuse.contents = FX.softDot
        sm.multiply.contents = UIColor.black
        sm.transparency = 0.6
        sm.writesToDepthBuffer = false
        sm.diffuse.contents = Tex.render(CGSize(width: 64, height: 64), key: "blob") { c, _ in
            let cs = CGColorSpaceCreateDeviceRGB()
            let g = CGGradient(colorsSpace: cs, colors: [UIColor(white: 0, alpha: 0.8).cgColor, UIColor(white: 0, alpha: 0).cgColor] as CFArray, locations: [0, 1])!
            c.drawRadialGradient(g, startCenter: CGPoint(x: 32, y: 32), startRadius: 0, endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
        }
        sm.multiply.contents = nil
        sh.materials = [sm]
        ballShadow.geometry = sh
        ballShadow.eulerAngles.x = -.pi / 2
        ballShadow.castsShadow = false
        scene.rootNode.addChildNode(ballShadow)
        // Landing marker for lofted balls.
        let lm = Geo.node(Geo.ring(inner: 0.35, outer: 0.45), Mat.emissive(UIColor(hex: 0xFFD23B), intensity: 1.6))
        landingMarker.addChildNode(lm)
        landingMarker.isHidden = true
        landingMarker.castsShadow = false
        scene.rootNode.addChildNode(landingMarker)
    }

    private func buildCamera() {
        camera.wantsHDR = true
        camera.fieldOfView = 25
        camera.zNear = 0.5
        camera.zFar = 400
        camera.bloomIntensity = 0.9
        camera.bloomThreshold = 1.0
        camera.bloomBlurRadius = 10
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = theme.night ? 0.1 : -0.1
        camera.vignettingIntensity = 0.55
        camera.vignettingPower = 1.2
        camera.saturation = 1.12
        camera.contrast = 0.08
        // No SSAO / colour fringe: the two priciest post effects, near-invisible from the match camera (phones ran hot).
        camera.screenSpaceAmbientOcclusionIntensity = 0
        camera.colorFringeStrength = 0
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 17, 17)
        cameraNode.look(at: SCNVector3(0, 0, 1))
        scene.rootNode.addChildNode(cameraNode)
    }

    // MARK: - Per-frame

    func update(state s: MatchState, prev: MatchState?, alpha: Float, dt: Float, human: PlayerState?, charge: Float, aim: V2) {
        time += dt
        let a = alpha
        // Players.
        for i in 0..<min(8, s.players.count) {
            let p = s.players[i]
            let q = prev?.players[i] ?? p
            let pos = lerp2(q.pos, p.pos, a)
            let node = playerNodes[i]
            node.position = SCNVector3(pos.x, 0, pos.y)
            var face = q.facing + angleDelta(q.facing, p.facing) * a
            if p.action == .celebrate, p.id == s.lastScorer, p.actionT > 1.6 {
                // Turn to the camera for the celebration.
                face = .pi / 2
            }
            rigs[i].root.eulerAngles.y = .pi / 2 - face
            rigs[i].root.position.y = p.height > 0 && p.action != .dive && p.action != .header ? p.height : 0
            let cosF = cos(face), sinF = sin(face)
            let local = V2(p.actionDir.x * sinF - p.actionDir.y * cosF, p.actionDir.x * cosF + p.actionDir.y * sinF)
            var pose = PoseInput()
            pose.speed = PannaCore.length(p.vel)
            pose.runPhase = p.runPhase
            pose.action = p.action
            pose.actionT = p.actionT
            pose.actionDur = p.actionDur
            pose.variant = p.action == .skill ? p.actionVariant : (p.action == .kick ? p.actionVariant : p.actionVariant)
            pose.charge = p.shotCharge
            pose.height = p.height
            pose.isKeeper = p.isKeeper
            pose.hasBall = s.ball.owner == i
            pose.time = time + Float(i) * 0.7
            pose.localDir = V2(-local.x, local.y)
            pose.sprint = PannaCore.length(p.vel) > 6.6
            pose.flow = p.inFlow
            pose.celebration = celebrations[i]
            rigs[i].pose(pose, dt: dt)
            // Flow ready / active visuals.
            readyRings[i].isHidden = !(p.hype >= 100 && !p.inFlow)
            if !readyRings[i].isHidden { readyRings[i].opacity = CGFloat(0.55 + 0.45 * sin(time * 8)) }
            if p.inFlow && auras[i] == nil {
                let col = UIColor(hex: rigs[i].appearance.trail)
                let au = FX.aura(color: col)
                node.addParticleSystem(au)
                auras[i] = au
            } else if !p.inFlow, let au = auras[i] {
                node.removeParticleSystem(au)
                auras[i] = nil
            }
        }
        // Human marker.
        if let h = human, humanId >= 0 {
            let n = playerNodes[humanId]
            humanArrow.position = SCNVector3(n.position.x, 2.55 + sin(time * 5) * 0.08, n.position.z)
            humanArrow.isHidden = s.phase == .goal || s.phase == .ended
            // Aim arrow while charging.
            if charge >= 0 && s.ball.owner == humanId {
                aimArrow.isHidden = false
                var d = aim
                if lengthSq(d) < 0.01 { d = PannaCore.normalized(V2(h.team == 0 ? shape.halfLength : -shape.halfLength, 0) - h.pos) }
                aimArrow.position = SCNVector3(n.position.x, 0.05, n.position.z)
                aimArrow.eulerAngles.y = atan2(d.x, d.y)
                let len = 1.2 + charge * 2.6
                aimArrow.scale = SCNVector3(1, 1, len)
                let perfect = charge >= 0.72 && charge <= 0.9
                aimArrow.childNodes.forEach { $0.geometry?.firstMaterial?.emission.contents = perfect ? UIColor(hex: 0x39FF88) : (charge > 0.9 ? UIColor(hex: 0xFF3B5C) : UIColor.white) }
            } else { aimArrow.isHidden = true }
            // Pass preview: which teammate a tap-pass would pick (same cone logic as the sim).
            if s.ball.owner == humanId && charge < 0 {
                let prefer: V2 = lengthSq(aim) > 0.01 ? PannaCore.normalized(aim) : (lengthSq(h.lastInput.move) > 0.04 ? PannaCore.normalized(h.lastInput.move) : h.facingDir)
                var best = -1
                var bestScore: Float = -99
                for m in s.players where m.team == h.team && m.id != humanId && !m.isKeeper {
                    let to = m.pos - h.pos
                    let ang = acos(max(-1, min(1, PannaCore.dot(PannaCore.normalized(to), prefer))))
                    if ang > 0.87 { continue }
                    let sc = 1 - ang / 0.87 - PannaCore.length(to) / 60
                    if sc > bestScore { bestScore = sc; best = m.id }
                }
                if best >= 0 {
                    let mn = playerNodes[best]
                    passMarker.isHidden = false
                    passMarker.position = SCNVector3(mn.position.x, 2.45 + sin(time * 7) * 0.06, mn.position.z)
                } else { passMarker.isHidden = true }
            } else { passMarker.isHidden = true }
        }
        // Ball.
        let b = s.ball
        let pb = prev?.ball ?? b
        let bp = pb.pos + (b.pos - pb.pos) * a
        ballNode.position = SCNVector3(bp.x, bp.y + BallState.radius * 0.7, bp.z)
        let sa = b.spinAngle
        ballVisual.eulerAngles = SCNVector3(sa.x, 0, sa.z)
        ballShadow.position = SCNVector3(bp.x, 0.015, bp.z)
        // Readability: a carried ball that has run away from the feet glows orange — the moment to tackle.
        var exposure: Float = 0
        if b.owner >= 0, b.owner < s.players.count {
            let o = s.players[b.owner].pos
            let d = PannaCore.length(V2(bp.x - o.x, bp.z - o.y))
            exposure = min(1, max(0, (d - 0.75) / 0.5))
        }
        exposureRing.position = SCNVector3(bp.x, 0.03, bp.z)
        exposureRing.opacity += (CGFloat(exposure) - exposureRing.opacity) * 0.3
        exposureRing.scale = SCNVector3(1 + sin(time * 12) * 0.08, 1, 1 + sin(time * 12) * 0.08)
        let hgt = max(0, bp.y - BallState.radius)
        let ss = 1 + hgt * 0.35
        ballShadow.scale = SCNVector3(ss, ss, ss)
        ballShadow.opacity = CGFloat(max(0.2, 0.9 - hgt * 0.12))
        let speed = PannaCore.length(b.vel)
        trail.birthRate = b.owner < 0 && speed > 15 ? CGFloat(min(220, (speed - 15) * 25)) : 0
        // Landing marker for lofted balls.
        if b.owner < 0 && b.pos.y > 1.2 && b.vel.y != 0 {
            let g = MatchSim.gravity
            let disc = b.vel.y * b.vel.y + 2 * g * (b.pos.y - BallState.radius)
            let tl = (b.vel.y + disc.squareRoot()) / g
            landingMarker.position = SCNVector3(b.pos.x + b.vel.x * tl, 0.03, b.pos.z + b.vel.z * tl)
            landingMarker.isHidden = false
            landingMarker.scale = SCNVector3(1 + sin(time * 10) * 0.08, 1, 1 + sin(time * 10) * 0.08)
        } else { landingMarker.isHidden = true }

        updateCamera(s, ball: bp, dt: dt, human: human)
    }

    var celebrations: [Int] = Array(repeating: 0, count: 8)

    private func updateCamera(_ s: MatchState, ball: SIMD3<Float>, dt: Float, human: PlayerState?) {
        let L = shape.halfLength
        var focus = SIMD3<Float>(ball.x, 0, ball.z)
        if let h = human, humanId >= 0, s.phase == .playing {
            focus = focus * 0.7 + SIMD3<Float>(h.pos.x, 0, h.pos.y) * 0.3
        }
        let bv = s.ball.vel
        focus += SIMD3<Float>(bv.x, 0, bv.z) * 0.12
        var height: Float = 14.5
        var back: Float = 24.5
        var lookZOffset: Float = -1.6
        // Push in when the ball is near a goal.
        let nearGoal = max(0, abs(ball.x) - (L - 12)) / 12
        height -= nearGoal * 1.6
        back -= nearGoal * 1.4
        focus.x = max(-L + 5, min(L - 5, focus.x))
        focus.z = max(-3, min(3.5, focus.z * 0.35))

        // Celebration cam: swoop onto the scorer.
        if s.phase == .goal || s.phase == .ended, s.lastScorer >= 0 {
            celebrationCam = min(1, celebrationCam + dt * 1.2)
        } else {
            celebrationCam = max(0, celebrationCam - dt * 2.5)
        }
        var targetPos = SIMD3<Float>(focus.x, height, focus.z + back)
        var lookAt = SIMD3<Float>(focus.x, 0, focus.z + lookZOffset)
        if celebrationCam > 0, s.lastScorer >= 0 {
            let sp = s.players[s.lastScorer].pos
            // Hero framing: close enough that the scorer fills half the frame, high enough to clear the boards.
            let cp = SIMD3<Float>(sp.x, 2.9, sp.y + 7.6)
            let cl = SIMD3<Float>(sp.x, 1.05, sp.y)
            let e = celebrationCam * celebrationCam * (3 - 2 * celebrationCam)
            targetPos = targetPos + (cp - targetPos) * e
            lookAt = lookAt + (cl - lookAt) * e
            lookZOffset = 0
        }
        // Opening flyover: low over the pitch facing the skyline, then swing up into the broadcast view.
        var k: Float = 1 - exp(-dt * 6)
        if s.phase == .kickoff && s.time == 0 && s.score == [0, 0] {
            let t = min(1, s.phaseT / 2.6)
            let e = t * t * (3 - 2 * t)
            let startPos = SIMD3<Float>(-14 + 10 * e, 2.2, 9)
            let startLook = SIMD3<Float>(4, 3.2, -30)
            targetPos = startPos + (targetPos - startPos) * e * e
            lookAt = startLook + (lookAt - startLook) * e * e
            if s.phaseT < 0.05 {
                cameraNode.position = SCNVector3(startPos.x, startPos.y, startPos.z)
                camTarget = startLook
            }
            k = 1 - exp(-dt * 10)
        }
        camTarget += (lookAt - camTarget) * k
        var pos = SIMD3<Float>(cameraNode.position.x, cameraNode.position.y, cameraNode.position.z)
        pos += (targetPos - pos) * k
        // Trauma² shake.
        trauma = max(0, trauma - dt * 1.4)
        let shake = trauma * trauma
        let ox = sin(time * 43) * 0.35 * shake, oy = sin(time * 37 + 1) * 0.3 * shake
        cameraNode.position = SCNVector3(pos.x, pos.y, pos.z)
        cameraNode.look(at: SCNVector3(camTarget.x + ox, camTarget.y + oy, camTarget.z))
        fovPunch = max(0, fovPunch - dt * 12)
        camera.fieldOfView = CGFloat(25 + fovPunch)
        // Colour grade for flow / slow-mo.
        let humanFlow = human?.inFlow ?? false
        flowGrade += ((humanFlow ? 1 : 0) - flowGrade) * min(1, dt * 4)
        camera.saturation = CGFloat(1.12 + flowGrade * 0.12)
        camera.bloomIntensity = RenderBudget.constrained ? 0 : CGFloat(0.9 + flowGrade * 0.35 + slowmoGrade * 0.6)
        camera.colorFringeStrength = CGFloat(0.4 + flowGrade * 1.2 + slowmoGrade * 1.5)
        camera.vignettingIntensity = CGFloat(0.55 + flowGrade * 0.35 + slowmoGrade * 0.3)
        camera.wantsDepthOfField = celebrationCam > 0.3
        camera.focusDistance = CGFloat(14 - celebrationCam * 6)
        camera.fStop = 2.8
    }

    // MARK: - Events

    func handle(_ e: MatchEvent, state s: MatchState) {
        switch e {
        case .kick(_, let power, _):
            let b = s.ball.pos
            spawn(FX.burst(color: .white, count: 60 + CGFloat(power) * 200, speed: 3 + CGFloat(power) * 4, life: 0.35, size: 0.08, image: FX.spark), at: SCNVector3(b.x, b.y, b.z))
            if power > 0.6 { fovPunch = 3 }
        case .shot(_, let perfect, let power):
            trauma = min(1, trauma + 0.2 + power * 0.25)
            if perfect {
                let b = s.ball.pos
                spawn(FX.burst(color: UIColor(hex: 0x39FF88), count: 400, speed: 7, life: 0.5, size: 0.18), at: SCNVector3(b.x, b.y, b.z))
                shockRing(color: UIColor(hex: 0x39FF88), at: SCNVector3(b.x, 0.05, b.z))   // unmistakable "you timed it" tell
                fovPunch = 5
            }
        case .goal(let team, _, _, _):
            trauma = 1
            let side: Float = team == 0 ? 1 : -1
            let gp = SCNVector3(side * (shape.halfLength + 0.5), 1.2, 0)
            spawn(FX.confetti(colors: [teamColors[team]]), at: SCNVector3(gp.x - side * 1.5, 0.2, -2.8))
            spawn(FX.confetti(colors: [teamColors[team]]), at: SCNVector3(gp.x - side * 1.5, 0.2, 2.8))
            spawn(FX.burst(color: teamColors[team].lighter(0.3), count: 900, speed: 9, life: 0.9, size: 0.22), at: gp)
            // Net bulge.
            let net = arena.nets[team == 0 ? 1 : 0]
            net.removeAllActions()
            net.runAction(.sequence([
                .moveBy(x: CGFloat(side * 0.45), y: 0, z: 0, duration: 0.08),
                .moveBy(x: CGFloat(-side * 0.55), y: 0, z: 0, duration: 0.2),
                .moveBy(x: CGFloat(side * 0.1), y: 0, z: 0, duration: 0.25),
            ]))
            arena.crowdCheer(intensity: 1)
            for l in arena.floodLights {
                let base = l.intensity
                l.intensity = base * 2.4
                SCNTransaction.begin(); SCNTransaction.animationDuration = 1.2; l.intensity = base; SCNTransaction.commit()
            }
        case .save(let k, _):
            let p = s.players[k].pos
            spawn(FX.burst(color: UIColor(hex: 0xE8FF3B), count: 250, speed: 5, life: 0.4, size: 0.12, image: FX.spark), at: SCNVector3(p.x, 1.2, p.y))
            trauma = min(1, trauma + 0.3)
        case .tackleWon(let t, _, let slide):
            let p = s.players[t].pos
            spawn(FX.burst(color: UIColor(hex: theme.floor == .sand ? 0xE0C090 : 0xBBD0BB), count: slide ? 300 : 120, speed: 2.5, life: 0.6, size: 0.25, gravity: true, spread: 60), at: SCNVector3(p.x, 0.2, p.y))
            trauma = min(1, trauma + 0.25)
        case .nutmeg(let a, _):
            let p = s.players[a].pos
            spawn(FX.burst(color: UIColor(hex: 0xFFD23B), count: 600, speed: 6, life: 0.6, size: 0.2), at: SCNVector3(p.x, 0.6, p.y))
            trauma = min(1, trauma + 0.35)
            arena.crowdCheer(intensity: 0.6)
        case .ankles(let a, _):
            let p = s.players[a].pos
            spawn(FX.burst(color: UIColor(hex: 0xFF3BD4), count: 350, speed: 5, life: 0.5, size: 0.16), at: SCNVector3(p.x, 0.6, p.y))
            arena.crowdCheer(intensity: 0.4)
        case .flowStart(let i):
            let p = s.players[i].pos
            // Crisp awakening: a sharp shockwave along the turf and speed-line sparks rising off the player.
            let fc = UIColor(hex: rigs[i].appearance.trail)
            shockRing(color: fc, at: SCNVector3(p.x, 0.04, p.y))
            let rise = FX.burst(color: fc, count: 140, speed: 9, life: 0.45, size: 0.09, image: FX.spark, spread: 18)
            rise.emittingDirection = SCNVector3(0, 1, 0)
            rise.particleSizeVariation = 0.03
            rise.orientationMode = .free
            rise.stretchFactor = 0.08
            spawn(rise, at: SCNVector3(p.x, 0.2, p.y))
            trauma = min(1, trauma + 0.4)
        case .wallHit(let sp, let x, let z):
            spawn(FX.burst(color: UIColor(hex: theme.neonA), count: CGFloat(min(200, sp * 12)), speed: 3, life: 0.3, size: 0.1, image: FX.spark), at: SCNVector3(x, 0.5, z))
            trauma = min(1, trauma + min(0.25, sp * 0.015))
        case .postHit:
            let b = s.ball.pos
            spawn(FX.burst(color: .white, count: 300, speed: 6, life: 0.4, size: 0.1, image: FX.spark), at: SCNVector3(b.x, b.y, b.z))
            trauma = min(1, trauma + 0.45)
        default: break
        }
    }

    private func shockRing(color: UIColor, at p: SCNVector3) {
        let plane = SCNPlane(width: 1, height: 1)
        let m = SCNMaterial()
        m.diffuse.contents = FX.ring
        m.multiply.contents = color
        m.lightingModel = .constant
        m.blendMode = .add
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        plane.materials = [m]
        let n = SCNNode(geometry: plane)
        n.eulerAngles.x = -.pi / 2
        n.position = p
        n.scale = SCNVector3(0.4, 0.4, 0.4)
        scene.rootNode.addChildNode(n)
        let grow = SCNAction.scale(to: 7, duration: 0.5); grow.timingMode = .easeOut
        n.runAction(.sequence([.group([grow, .fadeOut(duration: 0.5)]), .removeFromParentNode()]))
    }

    private func spawn(_ ps: SCNParticleSystem, at p: SCNVector3) {
        let n = SCNNode()
        n.position = p
        n.addParticleSystem(ps)
        scene.rootNode.addChildNode(n)
        n.runAction(.sequence([.wait(duration: 3.5), .removeFromParentNode()]))
    }
}
