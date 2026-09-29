import SceneKit
import PannaCore

/// Builds a full venue: sky, lighting, pitch, cage, goals, crowd, skyline.
final class ArenaBuilder {
    let theme: ArenaTheme
    let shape: ArenaShape
    let root = SCNNode()
    var crowd: [SCNNode] = []
    var nets: [SCNNode] = []      // [team0 goal (left), team1 goal (right)]
    var floodLights: [SCNLight] = []
    var ledStrips: [SCNMaterial] = []

    init(theme: ArenaTheme, shape: ArenaShape = .standard) {
        self.theme = theme
        self.shape = shape
    }

    func build(into scene: SCNScene) {
        scene.rootNode.addChildNode(root)
        sky(scene)
        lights(scene)
        ground()
        pitch()
        cage()
        goals()
        switch theme.props {
        case .stadium: stands(rows: 6, dense: true)
        default: stands(rows: 1, dense: false)
        }
        skyline()
        if theme.hasRoof { roof() }
        // Only players, ball and goals cast shadows; thin props make streaky artifacts.
        root.enumerateHierarchy { n, _ in n.castsShadow = false }
    }

    // MARK: Sky & light

    private func sky(_ scene: SCNScene) {
        let t = theme
        let img = Tex.render(CGSize(width: 512, height: 512), key: "sky-\(t.id)") { c, s in
            let cs = CGColorSpaceCreateDeviceRGB()
            let cols = [UIColor(hex: t.skyTop).cgColor, UIColor(hex: t.skyBottom).cgColor, UIColor(hex: t.horizonGlow).cgColor, UIColor(hex: t.surround).darker(0.6).cgColor] as CFArray
            let g = CGGradient(colorsSpace: cs, colors: cols, locations: [0, 0.42, 0.5, 0.56])!
            c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: s.height), options: [])
            if t.night {
                var seed: UInt64 = 99
                for _ in 0..<160 {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    let x = CGFloat(seed % 512), y = CGFloat((seed >> 12) % 200)
                    let a = CGFloat((seed >> 30) % 100) / 100
                    c.setFillColor(UIColor(white: 1, alpha: a * 0.8).cgColor)
                    c.fill(CGRect(x: x, y: y, width: 1.2, height: 1.2))
                }
            }
        }
        scene.background.contents = img
        scene.lightingEnvironment.contents = img
        scene.lightingEnvironment.intensity = t.night ? 0.35 : 1.1
        scene.fogColor = UIColor(hex: t.fog)
        scene.fogStartDistance = 45
        scene.fogEndDistance = 140
        scene.fogDensityExponent = 1.3
    }

    private func lights(_ scene: SCNScene) {
        let t = theme
        let amb = SCNLight()
        amb.type = .ambient
        amb.color = UIColor(hex: t.ambient)
        amb.intensity = t.night ? 160 : 480
        let an = SCNNode(); an.light = amb
        root.addChildNode(an)

        // Key light: moon / sun / main floodlight bank. Casts the shadows.
        let key = SCNLight()
        key.type = .directional
        key.color = UIColor(hex: t.key)
        key.intensity = t.keyIntensity * (t.night ? 0.45 : 1)
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.shadowSampleCount = 8
        key.shadowRadius = 3
        key.shadowColor = UIColor(white: 0, alpha: 0.55)
        key.orthographicScale = 26
        key.automaticallyAdjustsShadowProjection = false
        key.shadowCascadeCount = 1
        key.zNear = 1; key.zFar = 120
        let kn = SCNNode(); kn.light = key
        kn.position = SCNVector3(-12, 40, 22)
        kn.look(at: SCNVector3(0, 0, 0))
        root.addChildNode(kn)

        // Pools of floodlight on the pitch — the look of a real night game.
        if t.night {
            for (x, z) in [(-9.0, -3.0), (9.0, -3.0), (-9.0, 4.0), (9.0, 4.0)] as [(Float, Float)] {
                let sp = SCNLight()
                sp.type = .spot
                sp.color = UIColor(hex: t.flood)
                sp.intensity = 2600
                sp.spotInnerAngle = 30
                sp.spotOuterAngle = 72
                sp.attenuationStartDistance = 10
                sp.attenuationEndDistance = 40
                let sn = SCNNode(); sn.light = sp
                sn.position = SCNVector3(x * 1.3, 16, z * 2.4)
                sn.look(at: SCNVector3(x, 0, z))
                root.addChildNode(sn)
            }
        }
        // Fill + rim from the opposite side for the vinyl sheen.
        let rim = SCNLight()
        rim.type = .directional
        rim.color = UIColor(hex: t.neonA).mixed(with: .white, 0.5)
        rim.intensity = 450
        let rn = SCNNode(); rn.light = rim
        rn.position = SCNVector3(10, 10, -30)
        rn.look(at: SCNVector3Zero)
        root.addChildNode(rn)

        // Floodlight towers (visible fixtures + omni fill).
        let L = Float(shape.halfLength), W = Float(shape.halfWidth)
        let towers: [SCNVector3] = [SCNVector3(-L - 3, 0, -W - 3), SCNVector3(L + 3, 0, -W - 3), SCNVector3(-L - 3, 0, W + 4), SCNVector3(L + 3, 0, W + 4)]
        let metal = Mat.pbr(UIColor(white: 0.18, alpha: 1), rough: 0.4, metal: 0.8, rim: 0)
        for (i, p) in towers.enumerated() {
            let h: Float = theme.hasRoof ? 7.5 : 14
            // Near-side poles would stand between the camera and the goals — lights only.
            if !theme.hasRoof && p.z < 0 {
                let pole = SCNCylinder(radius: 0.18, height: CGFloat(h))
                root.addChildNode(Geo.node(pole, metal, at: SCNVector3(p.x, h / 2, p.z)))
            }
            let panel = SCNBox(width: 2.6, height: 1.4, length: 0.3, chamferRadius: 0.08)
            let pm = Mat.emissive(UIColor(hex: t.flood), intensity: 2.2)
            let pn = Geo.node(panel, pm, at: SCNVector3(p.x, h, p.z))
            pn.look(at: SCNVector3(0, 0, 0))
            root.addChildNode(pn)
            if i < 2 || true {
                let o = SCNLight()
                o.type = .omni
                o.color = UIColor(hex: t.flood)
                o.intensity = t.night ? 1100 : 300
                o.attenuationStartDistance = 8
                o.attenuationEndDistance = 55
                let on = SCNNode(); on.light = o
                on.position = SCNVector3(p.x * 0.8, h - 2, p.z * 0.8)
                root.addChildNode(on)
                floodLights.append(o)
            }
        }
    }

    // MARK: Ground

    private func ground() {
        let t = theme
        let floor = SCNFloor()
        floor.reflectivity = t.floor == .court || t.props == .neonCity ? 0.12 : 0.03
        floor.reflectionFalloffEnd = 6
        let m = Mat.textured(Tex.noise(256, seed: 3, base: UIColor(hex: t.surround), variance: 0.08), rough: 0.85, rim: 0)
        m.diffuse.contentsTransform = SCNMatrix4MakeScale(40, 40, 1)
        floor.materials = [m]
        let fn = SCNNode(geometry: floor)
        fn.position.y = -0.01
        root.addChildNode(fn)
    }

    private func pitch() {
        let t = theme
        let L = CGFloat(shape.halfLength), W = CGFloat(shape.halfWidth)
        let margin: CGFloat = 1.2
        let pw = (L + margin) * 2, ph = (W + margin) * 2
        let ppm: CGFloat = 48 // pixels per metre
        let size = CGSize(width: pw * ppm, height: ph * ppm)
        let chamfer = CGFloat(shape.chamfer)
        let img = Tex.render(size, key: "pitch-\(t.id)") { c, s in
            let A = UIColor(hex: t.pitchA), B = UIColor(hex: t.pitchB)
            c.setFillColor(A.darker(0.25).cgColor); c.fill(CGRect(origin: .zero, size: s))
            func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: (x + L + margin) * ppm, y: (y + W + margin) * ppm) }
            // Playing surface outline (chamfered).
            let outline = UIBezierPath()
            outline.move(to: P(-L + chamfer, -W)); outline.addLine(to: P(L - chamfer, -W)); outline.addLine(to: P(L, -W + chamfer))
            outline.addLine(to: P(L, W - chamfer)); outline.addLine(to: P(L - chamfer, W)); outline.addLine(to: P(-L + chamfer, W))
            outline.addLine(to: P(-L, W - chamfer)); outline.addLine(to: P(-L, -W + chamfer)); outline.close()
            c.saveGState()
            c.addPath(outline.cgPath); c.clip()
            c.setFillColor(A.cgColor); c.fill(CGRect(origin: .zero, size: s))
            switch t.floor {
            case .turf:
                // Mowing stripes.
                let n = 12
                for i in 0..<n where i % 2 == 0 {
                    let x0 = -L + CGFloat(i) * (2 * L / CGFloat(n))
                    c.setFillColor(B.cgColor)
                    c.fill(CGRect(origin: P(x0, -W), size: CGSize(width: 2 * L / CGFloat(n) * ppm, height: 2 * W * ppm)))
                }
                // Grain.
                var seed: UInt64 = 5
                for _ in 0..<Int(s.width * s.height / 90) {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    let x = CGFloat(seed % UInt64(s.width)), y = CGFloat((seed >> 20) % UInt64(s.height))
                    let v = CGFloat((seed >> 40) % 100) / 100
                    c.setFillColor(UIColor(white: v > 0.5 ? 1 : 0, alpha: 0.05).cgColor)
                    c.fill(CGRect(x: x, y: y, width: 2, height: 3))
                }
            case .court:
                c.setFillColor(B.cgColor)
                c.fill(CGRect(origin: P(-L * 0.5, -W), size: CGSize(width: L * ppm, height: 2 * W * ppm)))
                var seed: UInt64 = 11
                for _ in 0..<Int(s.width * s.height / 200) {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    let x = CGFloat(seed % UInt64(s.width)), y = CGFloat((seed >> 20) % UInt64(s.height))
                    c.setFillColor(UIColor(white: 1, alpha: 0.03).cgColor)
                    c.fill(CGRect(x: x, y: y, width: 3, height: 1))
                }
            case .sand, .concrete:
                var seed: UInt64 = 17
                for _ in 0..<Int(s.width * s.height / 40) {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    let x = CGFloat(seed % UInt64(s.width)), y = CGFloat((seed >> 20) % UInt64(s.height))
                    let v = CGFloat((seed >> 40) % 100) / 100
                    c.setFillColor((v > 0.5 ? B.lighter(0.2) : A.darker(0.15)).withAlphaComponent(0.5).cgColor)
                    c.fill(CGRect(x: x, y: y, width: 2, height: 2))
                }
            }
            // Lines.
            c.setStrokeColor(UIColor(hex: t.lines).withAlphaComponent(0.78).cgColor)
            c.setLineWidth(0.09 * ppm)
            c.addPath(outline.cgPath); c.strokePath()
            c.move(to: P(0, -W)); c.addLine(to: P(0, W)); c.strokePath()
            let cr: CGFloat = 3.2
            c.strokeEllipse(in: CGRect(origin: P(-cr, -cr), size: CGSize(width: 2 * cr * ppm, height: 2 * cr * ppm)))
            c.setFillColor(UIColor(hex: t.lines).cgColor)
            c.fillEllipse(in: CGRect(origin: P(-0.2, -0.2), size: CGSize(width: 0.4 * ppm, height: 0.4 * ppm)))
            // Boxes (arcs).
            for sx: CGFloat in [-1, 1] {
                let r: CGFloat = 6.5
                let center = P(sx * L, 0)
                c.addArc(center: center, radius: r * ppm, startAngle: sx > 0 ? .pi / 2 : -.pi / 2, endAngle: sx > 0 ? 3 * .pi / 2 : .pi / 2, clockwise: false)
                c.strokePath()
                let gr: CGFloat = 3.4
                c.addArc(center: center, radius: gr * ppm, startAngle: sx > 0 ? .pi / 2 : -.pi / 2, endAngle: sx > 0 ? 3 * .pi / 2 : .pi / 2, clockwise: false)
                c.strokePath()
                c.fillEllipse(in: CGRect(origin: P(sx * (L - 8) - 0.15, -0.15), size: CGSize(width: 0.3 * ppm, height: 0.3 * ppm)))
            }
            // Centre logo: "P" roundel.
            let logo = NSAttributedString(string: "PANNA", attributes: [
                .font: UIFont.systemFont(ofSize: 1.1 * ppm, weight: .black).rounded(),
                .foregroundColor: UIColor(hex: t.lines).withAlphaComponent(0.22), .kern: 0.3 * ppm,
            ])
            UIGraphicsPushContext(c)
            let ls = logo.size()
            let lp = P(0, 0)
            logo.draw(at: CGPoint(x: lp.x - ls.width / 2, y: lp.y - ls.height / 2 + 4.6 * ppm))
            UIGraphicsPopContext()
            c.restoreGState()
        }
        let plane = SCNPlane(width: pw, height: ph)
        let m = Mat.textured(img, rough: t.floor == .court ? 0.35 : 0.8, rim: 0)
        m.diffuse.wrapS = .clamp; m.diffuse.wrapT = .clamp
        m.diffuse.maxAnisotropy = 8
        plane.materials = [m]
        let n = SCNNode(geometry: plane)
        n.eulerAngles.x = -.pi / 2
        n.position.y = 0.001
        root.addChildNode(n)
    }

    // MARK: Cage

    private func ledTexture() -> UIImage {
        let t = theme
        return Tex.render(CGSize(width: 1024, height: 64), key: "led-\(t.id)") { c, s in
            c.setFillColor(UIColor.black.cgColor); c.fill(CGRect(origin: .zero, size: s))
            let words = ["PANNA", "STREET FOOTBALL", t.city.uppercased(), "NUTMEG = +HYPE", "PANNA", t.name]
            var x: CGFloat = 10
            var i = 0
            UIGraphicsPushContext(c)
            while x < s.width {
                let col = i % 2 == 0 ? UIColor(hex: t.neonA) : UIColor(hex: t.neonB)
                let str = NSAttributedString(string: words[i % words.count] + "  •  ", attributes: [
                    .font: UIFont.systemFont(ofSize: 40, weight: .black).rounded(), .foregroundColor: col,
                ])
                str.draw(at: CGPoint(x: x, y: 8))
                x += str.size().width
                i += 1
            }
            UIGraphicsPopContext()
        }
    }

    private func fenceTexture() -> UIImage {
        Tex.render(CGSize(width: 128, height: 128), key: "fence") { c, s in
            c.clear(CGRect(origin: .zero, size: s))
            c.setStrokeColor(UIColor(white: 0.75, alpha: 0.9).cgColor)
            c.setLineWidth(3)
            c.move(to: CGPoint(x: 0, y: 0)); c.addLine(to: CGPoint(x: 128, y: 128))
            c.move(to: CGPoint(x: 128, y: 0)); c.addLine(to: CGPoint(x: 0, y: 128))
            c.strokePath()
        }
    }

    private func cage() {
        let geo = ArenaGeometry(shape)
        let boardH: Float = 1.0
        let fenceH: Float = theme.hasRoof ? 5.5 : 5.2
        let boardMat = Mat.pbr(UIColor(hex: theme.wall), rough: 0.5, metal: 0.1, rim: 0.2)
        let led = Mat.emissive(.white, intensity: 1.4)
        led.emission.contents = ledTexture()
        led.emission.wrapS = .repeat
        ledStrips.append(led)
        let fenceMat = SCNMaterial()
        fenceMat.lightingModel = .physicallyBased
        fenceMat.diffuse.contents = fenceTexture()
        fenceMat.metalness.contents = 0.8
        fenceMat.roughness.contents = 0.4
        fenceMat.isDoubleSided = true
        fenceMat.transparencyMode = .aOne
        fenceMat.diffuse.wrapS = .repeat; fenceMat.diffuse.wrapT = .repeat
        fenceMat.writesToDepthBuffer = false
        let postMat = Mat.pbr(UIColor(white: 0.2, alpha: 1), rough: 0.35, metal: 0.9, rim: 0.2)

        // Board segments = player walls minus the goal mouths.
        let L = shape.halfLength
        for w in geo.playerWalls {
            let isMouth = abs(w.a.x) == L && abs(w.b.x) == L && abs(w.a.y) == shape.goalHalfWidth && abs(w.b.y) == shape.goalHalfWidth
            if isMouth { continue }
            // Skip goal box walls (handled by goals()).
            if abs(w.a.x) > L + 0.01 || abs(w.b.x) > L + 0.01 { continue }
            let d = w.b - w.a
            let len = PannaCore.length(d)
            let mid = (w.a + w.b) / 2
            let outward = PannaCore.normalized(V2(-d.y, d.x))
            let out = PannaCore.dot(outward, mid) > 0 ? outward : -outward
            let ang = atan2(d.y, d.x)
            let isEnd = abs(w.a.x) == L && abs(w.b.x) == L
            // Near side (facing the camera) stays low and open so it never blocks play.
            let nearSide = !isEnd && mid.y > 0 && abs(d.x) > abs(d.y)
            let nearCorner = mid.y > 0 && !isEnd && abs(d.x) <= abs(d.y) + 0.01 && abs(d.y) > 0.01
            let bh: Float = (nearSide || nearCorner) ? 0.45 : boardH
            // Board
            let board = SCNBox(width: CGFloat(len), height: CGFloat(bh), length: 0.18, chamferRadius: 0.04)
            let ledM = led.copy() as! SCNMaterial
            ledM.emission.contentsTransform = SCNMatrix4MakeScale(max(1, Float(len) / 9), 1, 1)
            board.materials = [ledM, boardMat, ledM, boardMat, boardMat, boardMat]
            let bn = SCNNode(geometry: board)
            bn.position = SCNVector3(mid.x + out.x * 0.12, bh / 2, mid.y + out.y * 0.12)
            bn.eulerAngles.y = -ang
            root.addChildNode(bn)
            // Neon tube along the top of the boards.
            let tube = SCNCylinder(radius: 0.03, height: CGFloat(len))
            let tn = Geo.node(tube, Mat.emissive(UIColor(hex: isEnd ? theme.neonB : theme.neonA), intensity: 2.5), at: SCNVector3(mid.x + out.x * 0.02, bh + 0.03, mid.y + out.y * 0.02))
            tn.eulerAngles = SCNVector3(0, -ang, Float.pi / 2)
            root.addChildNode(tn)
            if nearSide || nearCorner { continue }
            // Fence above (end walls stay low so goalmouths read clearly).
            let fh = isEnd ? 1.6 : fenceH - boardH
            let fence = SCNPlane(width: CGFloat(len), height: CGFloat(fh))
            let fm = fenceMat.copy() as! SCNMaterial
            fm.diffuse.contentsTransform = SCNMatrix4MakeScale(Float(len) / 0.6, fh / 0.6, 1)
            fence.materials = [fm]
            let fn = SCNNode(geometry: fence)
            fn.position = SCNVector3(mid.x + out.x * 0.2, boardH + fh / 2, mid.y + out.y * 0.2)
            fn.eulerAngles.y = -ang
            fn.renderingOrder = 10
            root.addChildNode(fn)
            // Posts + top rail.
            let posts = max(1, Int(len / 3))
            for k in 0...posts {
                let pp = w.a + d * (Float(k) / Float(posts))
                let post = SCNCylinder(radius: 0.05, height: CGFloat(boardH + fh))
                root.addChildNode(Geo.node(post, postMat, at: SCNVector3(pp.x + out.x * 0.2, (boardH + fh) / 2, pp.y + out.y * 0.2)))
            }
            let rail = SCNCylinder(radius: 0.045, height: CGFloat(len))
            let rn = Geo.node(rail, postMat, at: SCNVector3(mid.x + out.x * 0.2, boardH + fh, mid.y + out.y * 0.2))
            rn.eulerAngles = SCNVector3(0, -ang, Float.pi / 2)
            root.addChildNode(rn)
        }
    }

    // MARK: Goals

    private func netTexture() -> UIImage {
        Tex.render(CGSize(width: 64, height: 64), key: "net") { c, s in
            c.clear(CGRect(origin: .zero, size: s))
            c.setStrokeColor(UIColor(white: 1, alpha: 0.85).cgColor)
            c.setLineWidth(2.5)
            c.stroke(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
    }

    private func goals() {
        let L = shape.halfLength, g = shape.goalHalfWidth, h = shape.goalHeight, d = shape.goalDepth
        let postMat = Mat.pbr(.white, rough: 0.25, metal: 0.3, rim: 0.4)
        for sx: Float in [-1, 1] {
            let goal = SCNNode()
            root.addChildNode(goal)
            let r: CGFloat = 0.07
            for sz: Float in [-1, 1] {
                let post = SCNCylinder(radius: r, height: CGFloat(h))
                goal.addChildNode(Geo.node(post, postMat, at: SCNVector3(sx * L, h / 2, sz * g)))
            }
            let bar = SCNCylinder(radius: r, height: CGFloat(2 * g))
            let bn = Geo.node(bar, postMat, at: SCNVector3(sx * L, h, 0))
            bn.eulerAngles.x = .pi / 2
            goal.addChildNode(bn)
            // Nets.
            let net = SCNNode()
            let nm = SCNMaterial()
            nm.lightingModel = .physicallyBased
            nm.diffuse.contents = netTexture()
            nm.diffuse.wrapS = .repeat; nm.diffuse.wrapT = .repeat
            nm.isDoubleSided = true
            nm.transparencyMode = .aOne
            nm.writesToDepthBuffer = false
            nm.roughness.contents = 0.7
            func netPlane(_ w: Float, _ hh: Float) -> SCNPlane {
                let p = SCNPlane(width: CGFloat(w), height: CGFloat(hh))
                let m = nm.copy() as! SCNMaterial
                m.diffuse.contentsTransform = SCNMatrix4MakeScale(w / 0.18, hh / 0.18, 1)
                p.materials = [m]
                return p
            }
            let back = SCNNode(geometry: netPlane(2 * g, h))
            back.position = SCNVector3(sx * (L + d), h / 2, 0)
            back.eulerAngles.y = .pi / 2
            net.addChildNode(back)
            let roofN = SCNNode(geometry: netPlane(d, 2 * g))
            roofN.position = SCNVector3(sx * (L + d / 2), h, 0)
            roofN.eulerAngles.x = -.pi / 2
            net.addChildNode(roofN)
            for sz: Float in [-1, 1] {
                let side = SCNNode(geometry: netPlane(d, h))
                side.position = SCNVector3(sx * (L + d / 2), h / 2, sz * g)
                net.addChildNode(side)
            }
            net.renderingOrder = 12
            goal.addChildNode(net)
            nets.append(net)
            // Goal-line glow strip.
            let strip = SCNBox(width: 0.08, height: 0.01, length: CGFloat(2 * g), chamferRadius: 0)
            goal.addChildNode(Geo.node(strip, Mat.emissive(UIColor(hex: theme.neonA), intensity: 1.2), at: SCNVector3(sx * L, 0.006, 0)))
        }
        // Order: nets[0] = left goal (-x), nets[1] = right goal (+x)
    }

    // MARK: Crowd & skyline

    private func stands(rows: Int, dense: Bool) {
        let L = shape.halfLength, W = shape.halfWidth
        let standMat = Mat.pbr(UIColor(hex: theme.wall).lighter(0.08), rough: 0.7, rim: 0)
        let bodyGeo = SCNCapsule(capRadius: 0.22, height: 0.9)
        let headGeo = SCNSphere(radius: 0.16)
        let palette: [UInt32] = [theme.neonA, theme.neonB, 0xFFFFFF, 0x222222, 0xFFD23B, 0x3B8CFF, 0xFF8A3B, 0x7A7A8A]
        let mats = palette.map { Mat.pbr(UIColor(hex: $0).mixed(with: UIColor(hex: theme.fog), 0.55).darker(0.35), rough: 0.9, rim: 0.35, rimColor: UIColor(hex: theme.flood)) }
        let skinMats = Appearance.skinTones.map { Mat.pbr(UIColor(hex: $0).mixed(with: UIColor(hex: theme.fog), 0.25), rough: 0.7, rim: 0) }
        var seed: UInt64 = 1234
        func rnd() -> UInt64 { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return seed >> 16 }
        // Far side (negative z) bleachers plus the two ends.
        let spans: [(V2, V2, V2)] = [
            (V2(-L + 2, -W - 2.4), V2(L - 2, -W - 2.4), V2(0, -1)),
            (V2(-L - 2.8, -W + 3), V2(-L - 2.8, W - 3), V2(-1, 0)),
            (V2(L + 2.8, -W + 3), V2(L + 2.8, W - 3), V2(1, 0)),
        ]
        for (a, b, out) in (dense ? spans : Array(spans.prefix(1))) {
            let d = b - a
            let len = PannaCore.length(d)
            for r in 0..<rows {
                let step = V2(out.x, out.y) * (Float(r) * 0.9)
                let hgt = Float(r) * 0.55
                // Bleacher step.
                let stepBox = SCNBox(width: CGFloat(len), height: 0.5, length: 0.9, chamferRadius: 0)
                let sn = Geo.node(stepBox, standMat, at: SCNVector3((a.x + b.x) / 2 + step.x, hgt + 0.25, (a.y + b.y) / 2 + step.y))
                sn.eulerAngles.y = -atan2(d.y, d.x)
                root.addChildNode(sn)
                let count = Int(len / (dense ? 0.6 : 1.1))
                for k in 0..<count {
                    if !dense && rnd() % 3 == 0 { continue }
                    let t = (Float(k) + 0.5) / Float(count)
                    let p = a + d * t + step
                    let fan = SCNNode()
                    let body = SCNNode(geometry: bodyGeo.copy() as? SCNGeometry)
                    body.geometry?.materials = [mats[Int(rnd() % UInt64(mats.count))]]
                    body.position = SCNVector3(0, 0.45, 0)
                    fan.addChildNode(body)
                    let head = SCNNode(geometry: headGeo.copy() as? SCNGeometry)
                    head.geometry?.materials = [skinMats[Int(rnd() % UInt64(skinMats.count))]]
                    head.position = SCNVector3(0, 1.05, 0)
                    fan.addChildNode(head)
                    fan.position = SCNVector3(p.x + Float(Int(rnd() % 20) - 10) * 0.01, hgt + 0.5, p.y)
                    let sc = 0.9 + Float(rnd() % 20) / 100
                    fan.scale = SCNVector3(sc, sc, sc)
                    root.addChildNode(fan)
                    crowd.append(fan)
                    // Idle sway.
                    let delay = Double(rnd() % 100) / 60
                    let bob = SCNAction.sequence([.moveBy(x: 0, y: 0.06, z: 0, duration: 0.5 + delay * 0.2), .moveBy(x: 0, y: -0.06, z: 0, duration: 0.5 + delay * 0.2)])
                    fan.runAction(.sequence([.wait(duration: delay), .repeatForever(bob)]))
                }
            }
        }
    }

    func crowdCheer(intensity: Float = 1) {
        for (i, f) in crowd.enumerated() {
            let jump = SCNAction.sequence([
                .wait(duration: Double(i % 7) * 0.04),
                .moveBy(x: 0, y: CGFloat(0.5 * intensity), z: 0, duration: 0.18),
                .moveBy(x: 0, y: CGFloat(-0.5 * intensity), z: 0, duration: 0.22),
            ])
            f.runAction(.repeat(jump, count: 3), forKey: "cheer")
        }
    }

    private func windowTexture() -> UIImage {
        let t = theme
        return Tex.render(CGSize(width: 128, height: 256), key: "win-\(t.id)") { c, s in
            c.setFillColor(UIColor(hex: t.skyline).cgColor); c.fill(CGRect(origin: .zero, size: s))
            var seed: UInt64 = 77
            for y in stride(from: 8, to: 256, by: 14) {
                for x in stride(from: 8, to: 128, by: 14) {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    if (seed >> 33) % 3 == 0 {
                        c.setFillColor(UIColor(hex: t.windows).withAlphaComponent(CGFloat(60 + (seed >> 40) % 40) / 100).cgColor)
                        c.fill(CGRect(x: x, y: y, width: 8, height: 9))
                    }
                }
            }
        }
    }

    private func backdrop() -> Bool {
        guard let url = Bundle.main.url(forResource: "backdrop_" + theme.id, withExtension: "jpg"),
              let img = UIImage(contentsOfFile: url.path) else { return false }
        // A curved painted panorama behind the far side of the cage.
        let radius: Float = 46, span: Float = 2.7, height: Float = 64, segs = 40
        var verts: [SCNVector3] = [], uvs: [CGPoint] = [], idx: [Int32] = []
        for i in 0...segs {
            let t = Float(i) / Float(segs)
            let a = -Float.pi / 2 - span / 2 + span * t
            let x = cos(a) * radius * 1.45, z = sin(a) * radius + 12
            verts.append(SCNVector3(x, -24, z)); verts.append(SCNVector3(x, height - 24, z))
            uvs.append(CGPoint(x: CGFloat(t), y: 1)); uvs.append(CGPoint(x: CGFloat(t), y: 0))
        }
        for i in 0..<segs {
            let a = Int32(i * 2)
            idx += [a, a + 2, a + 1, a + 1, a + 2, a + 3]
        }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(textureCoordinates: uvs)],
                            elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = img
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.renderingOrder = -10
        n.castsShadow = false
        root.addChildNode(n)
        return true
    }

    private func skyline() {
        let t = theme
        if backdrop() { return }
        if t.props == .underground { return }
        var seed: UInt64 = 555
        func rnd() -> Float { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Float(seed >> 40) / Float(1 << 24) }
        let winMat = Mat.pbr(UIColor(hex: t.skyline), rough: 0.8, rim: 0)
        winMat.emission.contents = windowTexture()
        winMat.emission.intensity = t.night ? 1.0 : 0.25
        winMat.emission.wrapS = .repeat; winMat.emission.wrapT = .repeat
        // A ring of buildings behind the far side and ends.
        for i in 0..<34 {
            let ang = Float.pi * (1.05 + Float(i) / 33 * 0.9)   // behind the far side (negative z)
            let dist: Float = 48 + rnd() * 22
            let x = cos(ang) * dist * 1.3
            let z = sin(ang) * dist
            var h: Float
            var w: Float
            switch t.props {
            case .favela: h = 4 + rnd() * 8; w = 5 + rnd() * 5
            case .palms, .market: h = 3 + rnd() * 9; w = 6 + rnd() * 6
            case .stadium: h = 16 + rnd() * 6; w = 12
            default: h = 10 + rnd() * 34; w = 6 + rnd() * 8
            }
            let box = SCNBox(width: CGFloat(w), height: CGFloat(h), length: CGFloat(w * 0.8), chamferRadius: 0)
            let m = winMat.copy() as! SCNMaterial
            m.emission.contentsTransform = SCNMatrix4MakeScale(w / 8, h / 16, 1)
            if t.props == .favela {
                let cols: [UInt32] = [0xE8745A, 0xF2C14E, 0x5AA9E6, 0xB86ADE, 0x7FD17F, 0xF28AB5]
                m.diffuse.contents = UIColor(hex: cols[i % cols.count]).mixed(with: UIColor(hex: t.fog), 0.35)
            }
            box.materials = [m]
            let n = SCNNode(geometry: box)
            n.position = SCNVector3(x, h / 2 - (t.props == .favela ? Float(i % 3) : 0), z)
            n.eulerAngles.y = -ang
            root.addChildNode(n)
            // Neon signs on some buildings.
            if (t.props == .neonCity || t.props == .city) && i % 3 == 0 {
                let sign = SCNBox(width: CGFloat(w * 0.6), height: 1.6, length: 0.2, chamferRadius: 0.1)
                let sm = Mat.emissive(UIColor(hex: i % 2 == 0 ? t.neonA : t.neonB), intensity: 2.2)
                sign.materials = [sm]
                let sn = SCNNode(geometry: sign)
                sn.position = SCNVector3(x * 0.97, h * (0.5 + rnd() * 0.4), z * 0.97)
                sn.look(at: SCNVector3(0, sn.position.y, 0))
                root.addChildNode(sn)
            }
            if t.props == .palms && i % 2 == 0 { palm(at: SCNVector3(cos(ang) * 30 * 1.3, 0, sin(ang) * 30)) }
        }
        if t.props == .palms {
            for p in [SCNVector3(-24, 0, -16), SCNVector3(24, 0, -16), SCNVector3(-26, 0, 8), SCNVector3(26, 0, 8)] { palm(at: p) }
        }
    }

    private func palm(at p: SCNVector3) {
        let trunk = SCNCylinder(radius: 0.3, height: 8)
        let tm = Mat.pbr(UIColor(hex: 0x6A4A3A), rough: 0.8, rim: 0.1)
        let tn = Geo.node(trunk, tm, at: SCNVector3(p.x, 4, p.z))
        tn.eulerAngles.z = 0.08
        root.addChildNode(tn)
        let leafM = Mat.pbr(UIColor(hex: 0x2E7A4A), rough: 0.7, rim: 0.2)
        for i in 0..<7 {
            let leaf = SCNBox(width: 0.6, height: 0.08, length: 3.4, chamferRadius: 0.04)
            let ln = Geo.node(leaf, leafM, at: SCNVector3(p.x + 0.3, 8, p.z))
            ln.eulerAngles = SCNVector3(0.5, Float(i) / 7 * 2 * .pi, 0)
            ln.pivot = SCNMatrix4MakeTranslation(0, 0, -1.6)
            root.addChildNode(ln)
        }
    }

    private func roof() {
        let slab = SCNBox(width: 70, height: 1, length: 50, chamferRadius: 0)
        let m = Mat.pbr(UIColor(hex: 0x1A1B20), rough: 0.9, rim: 0)
        root.addChildNode(Geo.node(slab, m, at: SCNVector3(0, 9.5, 0)))
        // Pillars and strip lights.
        let pm = Mat.pbr(UIColor(hex: 0x2A2B30), rough: 0.8, rim: 0.1)
        for x in stride(from: -27, through: 27, by: 9) {
            for z in [-17, 19] {
                root.addChildNode(Geo.node(SCNBox(width: 1.2, height: 9.5, length: 1.2, chamferRadius: 0), pm, at: SCNVector3(Float(x), 4.75, Float(z))))
            }
        }
        for x in stride(from: -20, through: 20, by: 5) {
            let strip = SCNBox(width: 0.3, height: 0.1, length: 26, chamferRadius: 0)
            root.addChildNode(Geo.node(strip, Mat.emissive(UIColor(hex: theme.flood), intensity: 1.8), at: SCNVector3(Float(x), 8.95, 0)))
        }
        // Graffiti wall behind the far side.
        let g = Tex.render(CGSize(width: 1024, height: 256), key: "graffiti") { c, s in
            c.setFillColor(UIColor(hex: 0x2A2C32).cgColor); c.fill(CGRect(origin: .zero, size: s))
            let cols: [UInt32] = [theme.neonA, theme.neonB, 0xFFD23B, 0xFF8A3B, 0xFFFFFF]
            var seed: UInt64 = 8
            for _ in 0..<60 {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                c.setStrokeColor(UIColor(hex: cols[Int(seed >> 50) % cols.count]).withAlphaComponent(0.8).cgColor)
                c.setLineWidth(CGFloat(4 + (seed >> 20) % 12))
                c.setLineCap(.round)
                let x = CGFloat(seed % 1024), y = CGFloat((seed >> 12) % 256)
                c.move(to: CGPoint(x: x, y: y))
                c.addQuadCurve(to: CGPoint(x: x + CGFloat((seed >> 30) % 200) - 100, y: y + CGFloat((seed >> 40) % 120) - 60), control: CGPoint(x: x + 60, y: y - 80))
                c.strokePath()
            }
            let tag = NSAttributedString(string: "PANNA", attributes: [.font: UIFont.systemFont(ofSize: 150, weight: .black).rounded(), .foregroundColor: UIColor(hex: theme.neonB), .strokeColor: UIColor.black, .strokeWidth: -3])
            UIGraphicsPushContext(c); tag.draw(at: CGPoint(x: 300, y: 40)); UIGraphicsPopContext()
        }
        let wall = SCNPlane(width: 64, height: 9)
        let wm = Mat.pbr(.white, rough: 0.8, rim: 0)
        wm.diffuse.contents = g
        wall.materials = [wm]
        let wn = SCNNode(geometry: wall)
        wn.position = SCNVector3(0, 4.5, -18)
        root.addChildNode(wn)
    }
}
