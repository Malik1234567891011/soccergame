import SceneKit
import PannaCore
import simd

/// Per-frame animation inputs derived from sim state.
struct PoseInput {
    var speed: Float = 0
    var runPhase: Float = 0
    var action: ActionKind = .none
    var actionT: Float = 0
    var actionDur: Float = 1
    var variant: UInt8 = 0
    var charge: Float = -1
    var height: Float = 0
    var isKeeper = false
    var hasBall = false
    var celebration = 0
    var time: Float = 0
    var localDir: V2 = .zero   // action direction in character-local space (x = right, y = forward)
    var sprint = false
    var flow = false
}

/// An anime footballer: skinned mesh from Blender, cel-shaded, inked, with a runtime-drawn face.
final class CharacterRig {
    let root = SCNNode()
    let body = SCNNode()          // skeleton space; whole-body tilts (dives, flips, slides)
    let model: CharacterModel
    let unique: Bool
    private(set) var appearance: Appearance
    let isKeeper: Bool
    var boneNode: [String: SCNNode] = [:]
    private var bones: [SCNNode] = []
    private var restRot: [simd_quatf] = []
    private var headMaterial: SCNMaterial?
    let outlineColor: UIColor?
    let tinted: Bool
    private var expression: FaceExpression = .neutral
    private var blinkT: Float = 2
    private var exprHold: Float = 0
    var armCorrection: [simd_quatf] = [simd_quatf(angle: 0, axis: SIMD3(0, 0, 1)), simd_quatf(angle: 0, axis: SIMD3(0, 0, 1))]

    private var cur: [SCNVector3] = Array(repeating: SCNVector3Zero, count: 16)
    private var curHipsY: Float
    private var curBody = SCNVector3Zero
    private var curBodyY: Float = 0
    let hipHeight: Float
    let scale: Float

    init(appearance: Appearance, isKeeper: Bool = false, keeperColor: UInt32 = 0x2A2F3A, name: String = "", modelName: String? = nil, outlineColor: UIColor? = nil) {
        let chosen = modelName ?? appearance.look
        if let mn = chosen, let m = CharacterModel.load(mn), (!isKeeper || appearance.look != nil) { model = m; unique = true }
        else { model = CharacterModel.shared; unique = false }
        tinted = modelName == nil && appearance.look != nil
        self.outlineColor = outlineColor
        var a = appearance
        if isKeeper {
            a.primary = keeperColor; a.secondary = 0xE8FF3B; a.shirtPattern = .gradient; a.number = 1
            a.socks = keeperColor; a.sleeves = .long; a.accessory = .gloves
        }
        self.appearance = a
        self.isKeeper = isKeeper
        hipHeight = model.restWorld[model.boneIndex("hips")].columns.3.y
        curHipsY = hipHeight
        var sx: Float = 1, sy: Float = 1
        switch a.build {
        case .lean: sx = 0.93; sy = 1.02
        case .regular: break
        case .strong: sx = 1.1; sy = 1.0
        case .tall: sx = 0.98; sy = 1.07
        case .compact: sx = 1.04; sy = 0.93
        }
        scale = unique ? 1 : sy
        build(name: name)
        if !unique { body.scale = SCNVector3(sx, sy, sx) }
    }

    private func build(name: String) {
        let a = appearance
        root.addChildNode(body)
        defer { if unique == false { buildAccessories(a) } }
        // Skeleton.
        for (i, bn) in model.boneNames.enumerated() {
            let n = SCNNode()
            n.name = bn
            n.simdTransform = model.restLocal[i]
            bones.append(n)
            boneNode[bn] = n
            restRot.append(simd_quatf(model.restWorld[i]))
        }
        for (i, n) in bones.enumerated() {
            let p = model.boneParents[i]
            (p >= 0 ? bones[p] : body).addChildNode(n)
        }
        // Arms: rotate the A-pose rest to hanging straight down, which is what the pose code assumes.
        for (k, side) in ["R", "L"].enumerated() {
            let ua = model.restWorld[model.boneIndex("upperarm." + side)]
            let fa = model.restWorld[model.boneIndex("forearm." + side)]
            let d = simd_normalize(SIMD3(fa.columns.3.x - ua.columns.3.x, fa.columns.3.y - ua.columns.3.y, fa.columns.3.z - ua.columns.3.z))
            armCorrection[k] = simd_quatf(from: d, to: SIMD3(0, -1, 0))
        }

        if unique {
            buildUnique()
            return
        }
        // Materials.
        let skin = Toon.material(a.skinColor, spec: 0.0)
        let kitTex = KitTexture.shirt(a, name: name)
        let shirt = Toon.material(UIColor(hex: a.primary), texture: kitTex, spec: 0.0)
        let trim = Toon.material(UIColor(hex: a.secondary), spec: 0.0)
        let shorts = Toon.material(UIColor(hex: a.shorts), texture: KitTexture.shorts(a), spec: 0.0)
        let socks = Toon.material(UIColor(hex: a.socks), spec: 0.05)
        let band = Toon.material(UIColor(hex: a.secondary), spec: 0.05)
        let bootCol = UIColor(hex: a.bootColor)
        let boot = Toon.material(bootCol, spec: 0.5, rim: 0.7, emission: a.boots == .glow ? bootCol.withAlphaComponent(0.5) : nil)
        let sole = Toon.material(a.boots == .classic ? UIColor(white: 0.1, alpha: 1) : UIColor(hex: a.secondary).lighter(0.2), spec: 0.2)
        let accent = Toon.material(UIColor(hex: a.secondary), spec: 0.3)
        let hair = Toon.material(a.hairUIColor, texture: Toon.hairTexture(a.hairUIColor), spec: 0.0, rim: 0.55)
        let armMat: SCNMaterial = {
            switch a.sleeves {
            case .short: return skin
            case .long: return Toon.material(UIColor(hex: a.primary), spec: 0.1)
            case .compression: return Toon.material(UIColor(hex: a.secondary).darker(0.25), spec: 0.4)
            }
        }()
        let gloves = (a.accessory == .gloves) ? Toon.material(isKeeper ? UIColor(hex: 0xE8FF3B) : UIColor(hex: a.secondary), spec: 0.3) : skin
        let hm = Toon.material(a.skinColor, texture: FaceTexture.image(a, .neutral), spec: 0.0)
        hm.diffuse.wrapS = .repeat
        headMaterial = hm
        let outline = Toon.outlineMaterial(color: outlineColor)
        let hairOutline = Toon.outlineMaterial(width: 0.006, color: outlineColor)
        let byName: [String: SCNMaterial] = [
            "skin": skin, "skin_arm": armMat, "shirt": shirt, "trim": trim, "shorts": shorts, "socks": socks,
            "sockband": band, "boot": boot, "sole": sole, "bootaccent": accent, "hair": hair, "head": hm,
        ]
        let hairStyle = model.hairStyles.contains(a.hairStyle.rawValue) ? a.hairStyle.rawValue : (model.hairStyles.first ?? "")
        let hideHair = a.hairStyle == .bald || [.beanie, .cap].contains(a.headwear)
        let rootBone = bones[model.boneIndex("hips")]
        _ = rootBone
        let boneInv = model.restWorld.map { NSValue(scnMatrix4: SCNMatrix4(simd_inverse($0))) }
        for m in model.meshes {
            if m.slot.hasPrefix("hair:") && (m.slot != "hair:" + hairStyle || hideHair) { continue }
            var mats = m.materialNames.map { byName[$0] ?? skin }
            if m.slot == "hands" { mats = mats.map { _ in gloves } }
            mats.append(m.slot.hasPrefix("hair:") ? hairOutline : outline)
            let g = SCNGeometry(sources: m.sources, elements: m.elements + [m.outlineElement])
            g.materials = mats
            let node = SCNNode(geometry: g)
            node.name = m.name
            let sk = SCNSkinner(baseGeometry: g, bones: bones, boneInverseBindTransforms: boneInv, boneWeights: m.boneWeights, boneIndices: m.boneIndices)
            sk.skeleton = body
            node.skinner = sk
            node.castsShadow = true
            body.addChildNode(node)
        }
    }

    /// Painted AI-mesh characters: one baked texture, light cel ramp on top of the painted shading.
    private func buildUnique() {
        let boneInv = model.restWorld.map { NSValue(scnMatrix4: SCNMatrix4(simd_inverse($0))) }
        let a = appearance
        let kit = tinted ? Toon.Kit(primary: UIColor(hex: a.primary), secondary: UIColor(hex: a.secondary), shorts: UIColor(hex: a.shorts), socks: UIColor(hex: a.socks)) : nil
        let mat = Toon.paintedMaterial(texture: model.texture, kit: kit, shadow: SIMD3(0.8, 0.78, 0.9))
        mat.diffuse.wrapS = .clamp; mat.diffuse.wrapT = .clamp
        let outline = Toon.outlineMaterial(width: 0.012, color: outlineColor)
        for m in model.meshes {
            let g = SCNGeometry(sources: m.sources, elements: m.elements + [m.outlineElement])
            g.materials = m.elements.map { _ in mat } + [outline]
            let node = SCNNode(geometry: g)
            let sk = SCNSkinner(baseGeometry: g, bones: bones, boneInverseBindTransforms: boneInv, boneWeights: m.boneWeights, boneIndices: m.boneIndices)
            sk.skeleton = body
            node.skinner = sk
            node.castsShadow = true
            body.addChildNode(node)
        }
    }

    /// A child of `bone` whose frame equals the rest body frame (so attachments use model coordinates).
    private func attachFrame(_ bone: String) -> SCNNode {
        let i = model.boneIndex(bone)
        let n = SCNNode()
        n.simdTransform = simd_inverse(model.restWorld[i])
        bones[i].addChildNode(n)
        return n
    }

    private func buildAccessories(_ a: Appearance) {
        let hc = SCNVector3(model.headCenter.x, model.headCenter.y, model.headCenter.z)
        let r = model.headRadius
        let head = attachFrame("head")
        let sec = UIColor(hex: a.secondary)
        let outline = Toon.outlineMaterial(width: 0.008)
        func add(_ g: SCNGeometry, _ m: SCNMaterial, _ p: SCNVector3, to parent: SCNNode) -> SCNNode {
            g.materials = [m]
            let n = SCNNode(geometry: g)
            n.position = p
            // Ink outline shell.
            let o = SCNNode(geometry: g.copy() as? SCNGeometry)
            o.geometry?.materials = [outline]
            n.addChildNode(o)
            parent.addChildNode(n)
            return n
        }
        switch a.headwear {
        case .none: break
        case .headband:
            let t = SCNTorus(ringRadius: CGFloat(r * 0.97), pipeRadius: 0.028)
            let n = add(t, Toon.material(sec), hc + SCNVector3(0, r * 0.4, -0.005), to: head)
            n.scale = SCNVector3(0.95, 1, 0.98)
            n.eulerAngles.x = -0.14
        case .bandana, .durag:
            let cap = Geo.cap(radius: CGFloat(r * 1.1), frontTheta: 1.15, backTheta: 1.9, sideTheta: 1.5)
            let n = add(cap, Toon.material(a.headwear == .durag ? UIColor(hex: a.primary).darker(0.25) : sec, spec: a.headwear == .durag ? 0.6 : 0.1), hc, to: head)
            n.scale = SCNVector3(0.95, 1.05, 1)
        case .beanie:
            let cap = Geo.cap(radius: CGFloat(r * 1.14), frontTheta: 1.1, backTheta: 1.55, sideTheta: 1.4)
            _ = add(cap, Toon.material(sec), hc + SCNVector3(0, r * 0.05, 0), to: head)
            _ = add(SCNSphere(radius: 0.06), Toon.material(UIColor(hex: a.primary)), hc + SCNVector3(0, r * 1.2, 0), to: head)
        case .cap:
            let m = Toon.material(sec)
            _ = add(Geo.cap(radius: CGFloat(r * 1.1), frontTheta: 1.2, backTheta: 1.45, sideTheta: 1.35), m, hc, to: head)
            let brim = add(SCNCylinder(radius: 0.14, height: 0.02), m, hc + SCNVector3(0, r * 0.42, r * 1.02), to: head)
            brim.scale = SCNVector3(1, 1, 0.8)
            brim.eulerAngles.x = 0.15
        }
        switch a.accessory {
        case .goggles:
            _ = add(SCNBox(width: 0.28, height: 0.07, length: 0.05, chamferRadius: 0.03), Toon.material(UIColor(hex: 0x3BE8FF), spec: 0.9, rim: 0.9), hc + SCNVector3(0, r * 0.52, r * 0.88), to: head)
        case .mask:
            _ = add(SCNBox(width: 0.24, height: 0.1, length: 0.07, chamferRadius: 0.035), Toon.material(UIColor(white: 0.08, alpha: 1)), hc + SCNVector3(0, -r * 0.35, r * 0.82), to: head)
        case .chain:
            let chest = attachFrame("chest")
            let c = add(SCNTorus(ringRadius: 0.12, pipeRadius: 0.013), Toon.material(UIColor(hex: 0xFFD23B), spec: 0.9), SCNVector3(0, 1.4, 0.09), to: chest)
            c.eulerAngles.x = 1.25
        case .captainBand:
            let ua = attachFrame("upperarm.L")
            let t = model.restWorld[model.boneIndex("upperarm.L")].columns.3
            let n = add(SCNCylinder(radius: 0.09, height: 0.05), Toon.material(UIColor(hex: 0xFFD23B)), SCNVector3(t.x + 0.06, t.y - 0.1, t.z), to: ua)
            n.eulerAngles.z = 0.6
        case .wristbands:
            for side in ["L", "R"] {
                let fa = attachFrame("forearm." + side)
                let w = model.restWorld[model.boneIndex("hand." + side)].columns.3
                let e = model.restWorld[model.boneIndex("forearm." + side)].columns.3
                let p = SCNVector3(e.x + (w.x - e.x) * 0.8, e.y + (w.y - e.y) * 0.8, e.z)
                let n = add(SCNCylinder(radius: 0.058, height: 0.06), Toon.material(sec), p, to: fa)
                n.eulerAngles.z = side == "L" ? 0.55 : -0.55
            }
        default: break
        }
    }

    // MARK: - Bone solve

    private func setBone(_ name: String, _ e: SCNVector3, correction: simd_quatf? = nil) {
        let i = model.boneIndex(name)
        guard i < bones.count else { return }
        let qx = simd_quatf(angle: e.x, axis: SIMD3(1, 0, 0))
        let qy = simd_quatf(angle: e.y, axis: SIMD3(0, 1, 0))
        let qz = simd_quatf(angle: e.z, axis: SIMD3(0, 0, 1))
        var E = qx * qy * qz
        if let c = correction { E = E * c }
        let p = model.boneParents[i]
        let wp = p >= 0 ? restRot[p] : simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
        bones[i].simdOrientation = wp.inverse * E * restRot[i]
        let t = model.restLocal[i].columns.3
        if name != "hips" { bones[i].simdPosition = SIMD3(t.x, t.y, t.z) }
    }

    // MARK: - Face

    private func updateExpression(_ p: PoseInput, dt: Float) {
        var want: FaceExpression
        switch p.action {
        case .celebrate: want = .happy
        case .ankles, .knockdown: want = .shocked
        case .stumble: want = .hurt
        case .kick, .skill, .tackle, .slide, .header, .dive: want = .fierce
        default: want = p.charge >= 0 ? .fierce : .neutral
        }
        if p.flow { want = .flow }
        exprHold = max(0, exprHold - dt)
        blinkT -= dt
        if want == .neutral && blinkT < 0 {
            want = .blink
            if blinkT < -0.12 { blinkT = Float.random(in: 2.2...4.5) }
        }
        if want != expression && (exprHold <= 0 || want == .flow || want == .happy) {
            expression = want
            exprHold = want == .blink ? 0 : 0.25
            headMaterial?.diffuse.contents = FaceTexture.image(appearance, want)
            headMaterial?.emission.contents = want == .flow ? FaceTexture.glow(appearance) : nil
        }
    }

    private func sm(_ i: Int, _ target: SCNVector3, _ k: Float) -> SCNVector3 {
        let c = cur[i]
        let n = SCNVector3(c.x + (target.x - c.x) * k, c.y + (target.y - c.y) * k, c.z + (target.z - c.z) * k)
        cur[i] = n
        return n
    }

    func pose(_ p: PoseInput, dt: Float) {
        var hipL = SCNVector3Zero, hipR = SCNVector3Zero, kneeL = SCNVector3Zero, kneeR = SCNVector3Zero
        var shL = SCNVector3(0, 0, -0.12), shR = SCNVector3(0, 0, 0.12), elL = SCNVector3(-0.3, 0, 0), elR = SCNVector3(-0.3, 0, 0)
        var spineR = SCNVector3Zero, headR = SCNVector3Zero
        var ankL = SCNVector3Zero, ankR = SCNVector3Zero
        var hipsY = hipHeight
        var bodyRot = SCNVector3Zero
        var bodyY: Float = 0
        var k = 1 - exp(-dt * 20)

        let amp = min(p.speed / 7.0, 1.0)
        let stride: Float = p.sprint ? 2.1 : 1.7
        let a = p.runPhase / stride * 2 * .pi
        // Locomotion base.
        if amp > 0.05 {
            let sw: Float = 0.95 * amp
            hipL.x = -sin(a) * sw
            hipR.x = sin(a) * sw
            kneeL.x = max(0, cos(a)) * 1.35 * amp + 0.1
            kneeR.x = max(0, -cos(a)) * 1.35 * amp + 0.1
            shL.x = sin(a) * 0.8 * amp
            shR.x = -sin(a) * 0.8 * amp
            elL.x = -0.4 - amp * 0.8
            elR.x = -0.4 - amp * 0.8
            spineR.x = 0.12 + amp * (p.sprint ? 0.28 : 0.16)
            spineR.y = sin(a) * 0.12 * amp
            hipsY = hipHeight - 0.03 * amp + abs(sin(a)) * 0.06 * amp
            headR.x = -spineR.x * 0.6
        } else {
            // Idle: athletic stance, breathing.
            let br = sin(p.time * 2.4) * 0.03
            hipL.x = -0.12; hipR.x = 0.05
            kneeL.x = 0.25; kneeR.x = 0.18
            hipL.z = -0.08; hipR.z = 0.08
            spineR.x = 0.1 + br
            shL.z = -0.2; shR.z = 0.2
            elL.x = -0.5; elR.x = -0.5
            hipsY = hipHeight - 0.05 + br * 0.3
            headR.x = -0.05
        }
        if p.hasBall && amp > 0.1 { spineR.x += 0.08 }

        // Shot wind-up while charging.
        if p.charge >= 0 && p.action == .none {
            let c = min(p.charge, 1)
            hipR.x = 0.9 * c; kneeR.x = 1.2 * c
            spineR.x = -0.1 * c; spineR.y = -0.35 * c
            shL.z = -0.7 * c; shR.z = 0.5 * c
            shL.x = -0.4 * c
        }

        let t = p.actionT
        let prog = min(t / max(p.actionDur, 0.01), 1)
        switch p.action {
        case .kick:
            k = 1 - exp(-dt * 38)
            let lofted = p.variant == 1
            if p.variant == 2 {
                // Bicycle kick.
                bodyRot.x = -Float.pi * min(t / 0.45, 1.1)
                bodyY = sin(min(t / 0.7, 1) * .pi) * 0.9
                hipR.x = -1.6 + sin(t * 18) * 0.6; hipL.x = 0.8
                shL.z = -1.4; shR.z = 1.4
            } else if prog < 0.35 {
                hipR.x = 0.9; kneeR.x = 1.5; spineR.x = -0.12
                shL.z = -0.9; shR.z = 0.6
            } else {
                let f = (prog - 0.35) / 0.65
                hipR.x = -1.3 - (lofted ? 0.4 : 0) + f * 0.6
                kneeR.x = 0.15
                hipL.x = 0.1; kneeL.x = 0.35
                spineR.x = -0.22 - (lofted ? 0.15 : 0)
                shL.z = -1.0; shR.z = 0.7; shL.x = -0.5
                bodyY = 0.04
            }
        case .header:
            bodyY = p.height * 0.9
            headR.x = t < 0.2 ? -0.5 : 0.6
            spineR.x = t < 0.2 ? -0.3 : 0.4
            shL.z = -0.9; shR.z = 0.9; shL.x = -0.6; shR.x = -0.6
            hipL.x = 0.4; kneeL.x = 1.2; hipR.x = -0.2; kneeR.x = 0.6
        case .tackle:
            k = 1 - exp(-dt * 35)
            hipR.x = -1.35; kneeR.x = 0.1
            hipL.x = 0.5; kneeL.x = 0.9
            spineR.x = 0.35
            shL.z = -0.8; shR.z = 0.8
            hipsY = hipHeight - 0.18
        case .slide:
            k = 1 - exp(-dt * 30)
            bodyRot.x = -1.05
            bodyY = -0.25
            hipsY = hipHeight * 0.55
            hipR.x = -1.1; kneeR.x = 0.05
            hipL.x = -0.3; kneeL.x = 1.4
            shL.x = 0.8; shL.z = -0.5; shR.z = 1.0; elL.x = -0.2
            spineR.x = 0.5
        case .skill:
            k = 1 - exp(-dt * 34)
            let ph = t / max(p.actionDur, 0.01)
            switch p.variant {
            case 0: // step over: legs circle the ball
                hipL.z = sin(ph * 2 * .pi) * 0.55; hipL.x = -0.4
                hipR.z = sin(ph * 2 * .pi + .pi) * 0.55
                spineR.y = sin(ph * 2 * .pi) * 0.4
                shL.z = -0.8; shR.z = 0.8
            case 1: // elastico: outside then inside
                hipR.z = ph < 0.5 ? 0.6 : -0.5; hipR.x = -0.5
                spineR.z = ph < 0.5 ? -0.2 : 0.25
                shL.z = -1.0; shR.z = 0.7
            case 2: // roulette: spin is in root rotation
                hipL.x = -0.3; hipR.x = 0.3; shL.z = -0.9; shR.z = 0.9
            case 3: // croqueta
                hipL.z = -0.4; hipR.z = 0.4; hipsY -= 0.1
                spineR.z = p.localDir.x > 0 ? 0.3 : -0.3
            case 4: // rainbow flick
                hipR.x = 0.6; kneeR.x = 2.0; hipL.x = -0.5
                spineR.x = 0.3; shL.z = -0.9; shR.z = 0.9
            default: // drag back
                hipR.x = ph < 0.4 ? -0.8 : 0.4; kneeR.x = 0.2
                spineR.x = -0.2
            }
            hipsY -= 0.05
        case .stumble:
            spineR.x = 0.45 + sin(t * 20) * 0.15
            spineR.z = sin(t * 13) * 0.25
            shL.z = -1.2 + sin(t * 17) * 0.4; shR.z = 1.2 - sin(t * 15) * 0.4
            hipL.x = -0.4; kneeL.x = 0.6
            hipsY = hipHeight - 0.1
        case .ankles:
            k = 1 - exp(-dt * 14)
            hipsY = 0.22
            hipL.x = -1.45; hipR.x = -1.3; kneeL.x = 0.2; kneeR.x = 0.4
            hipL.z = -0.25; hipR.z = 0.25
            spineR.x = -0.55
            shL.x = 0.9; shR.x = 0.9; elL.x = -0.1; elR.x = -0.1
            headR.x = 0.2; headR.y = sin(t * 6) * 0.3
        case .knockdown:
            k = 1 - exp(-dt * 16)
            bodyRot.x = 1.35
            bodyY = -0.62
            shL.x = -2.4; shR.x = -2.2
            hipL.x = 0.2; hipR.x = 0.1
        case .dive:
            k = 1 - exp(-dt * 26)
            let side: Float = p.localDir.x >= 0 ? 1 : -1
            let dp = min(t / 0.3, 1)
            bodyRot.z = -side * 1.35 * dp
            bodyY = p.height + 0.1 * dp
            shL.z = -2.8; shR.z = 2.8
            elL.x = 0; elR.x = 0
            hipL.z = -0.3; hipR.z = 0.3
        case .keeperHold:
            shL.x = -1.2; shR.x = -1.2; shL.z = 0.35; shR.z = -0.35
            elL.x = -1.1; elR.x = -1.1
        case .celebrate:
            celebrate(p, &hipL, &hipR, &kneeL, &kneeR, &shL, &shR, &elL, &elR, &spineR, &headR, &hipsY, &bodyRot, &bodyY)
            k = 1 - exp(-dt * 16)
        case .none:
            break
        }
        if p.isKeeper && p.action == .none && amp < 0.3 {
            // Keeper ready stance.
            hipsY = hipHeight - 0.14
            kneeL.x = 0.6; kneeR.x = 0.6; hipL.x = -0.35; hipR.x = -0.35; hipL.z = -0.2; hipR.z = 0.2
            spineR.x = 0.35
            shL.z = -0.6; shR.z = 0.6; shL.x = -0.6; shR.x = -0.6; elL.x = -0.8; elR.x = -0.8
        }

        let jHipL = sm(0, hipL, k), jHipR = sm(1, hipR, k)
        let jKneeL = sm(2, kneeL, k), jKneeR = sm(3, kneeR, k)
        let jShL = sm(4, shL, k), jShR = sm(5, shR, k)
        let jElL = sm(6, elL, k), jElR = sm(7, elR, k)
        let jSpine = sm(8, spineR, k), jHead = sm(9, headR, k)
        let jAnkL = sm(10, ankL, k), jAnkR = sm(11, ankR, k)
        // Index 0 is the character's right side (-x), index 1 the left (+x).
        setBone("thigh.R", jHipL); setBone("thigh.L", jHipR)
        setBone("shin.R", jKneeL); setBone("shin.L", jKneeR)
        setBone("foot.R", jAnkL); setBone("foot.L", jAnkR)
        setBone("upperarm.R", jShL, correction: armCorrection[0]); setBone("upperarm.L", jShR, correction: armCorrection[1])
        setBone("forearm.R", jElL); setBone("forearm.L", jElR)
        setBone("spine", jSpine * 0.5); setBone("chest", jSpine * 0.5)
        setBone("neck", jHead * 0.35); setBone("head", jHead * 0.65)
        curHipsY += (hipsY - curHipsY) * k
        if let hb = boneNode["hips"] {
            let i = model.boneIndex("hips")
            let rest = model.restLocal[i].columns.3
            hb.simdPosition = SIMD3(rest.x, rest.y + (curHipsY - hipHeight), rest.z)
        }
        let kb = p.action == .kick && p.variant == 2 ? Float(1) : k
        curBody = SCNVector3(curBody.x + (bodyRot.x - curBody.x) * kb, curBody.y + (bodyRot.y - curBody.y) * kb, curBody.z + (bodyRot.z - curBody.z) * kb)
        body.eulerAngles = curBody
        curBodyY += (bodyY - curBodyY) * k
        body.position.y = curBodyY
        updateExpression(p, dt: dt)
    }

    private func celebrate(_ p: PoseInput, _ hipL: inout SCNVector3, _ hipR: inout SCNVector3, _ kneeL: inout SCNVector3, _ kneeR: inout SCNVector3,
                           _ shL: inout SCNVector3, _ shR: inout SCNVector3, _ elL: inout SCNVector3, _ elR: inout SCNVector3,
                           _ spineR: inout SCNVector3, _ headR: inout SCNVector3, _ hipsY: inout Float, _ bodyRot: inout SCNVector3, _ bodyY: inout Float) {
        let t = p.actionT
        let running = p.speed > 1.5
        if running && t < 1.6 {
            // Arms out while running to the corner.
            shL.z = -1.3; shR.z = 1.3; elL.x = -0.1; elR.x = -0.1
            return
        }
        let ct = max(0, t - (running ? 1.6 : 0.2))
        switch Celebration(rawValue: p.celebration) ?? .siu {
        case .siu:
            if ct < 0.5 {
                bodyY = sin(ct / 0.5 * .pi) * 0.7
                bodyRot.y = ct / 0.5 * .pi
                hipL.x = -0.4; kneeL.x = 1.0; hipR.x = 0.2; kneeR.x = 1.2
                shL.z = -1.0; shR.z = 1.0
            } else {
                bodyRot.y = .pi
                hipL.z = -0.35; hipR.z = 0.35
                shL.z = -0.55; shR.z = 0.55; shL.x = 0.3; shR.x = 0.3
                spineR.x = -0.25; headR.x = -0.35
                elL.x = -0.1; elR.x = -0.1
            }
        case .kneeSlide:
            hipsY = 0.35
            hipL.x = -0.1; kneeL.x = 1.7; hipR.x = -0.1; kneeR.x = 1.7
            spineR.x = -0.5; headR.x = -0.5
            shL.z = -2.3; shR.z = 2.3; elL.x = 0; elR.x = 0
        case .airplane:
            shL.z = -1.55; shR.z = 1.55; elL.x = 0; elR.x = 0
            bodyRot.z = sin(ct * 3) * 0.35
            spineR.x = 0.2
            let a = ct * 7
            hipL.x = -sin(a) * 0.5; hipR.x = sin(a) * 0.5
        case .backflip:
            let f = min(ct / 0.8, 1)
            bodyRot.x = -2 * .pi * f
            bodyY = sin(f * .pi) * 1.1
            kneeL.x = 1.4 * sin(f * .pi); kneeR.x = 1.4 * sin(f * .pi); hipL.x = -1.0 * sin(f * .pi); hipR.x = -1.0 * sin(f * .pi)
            shL.z = -2.6 * (1 - f) - 0.3; shR.z = 2.6 * (1 - f) + 0.3
        case .shush:
            shR.x = -2.4; elR.x = -2.2; shR.z = -0.25
            shL.z = -0.3
            headR.x = 0.1
        case .robot:
            let step = Float(Int(ct * 4) % 4)
            shL.x = step == 0 ? -1.5 : (step == 2 ? 0 : -0.8); elL.x = -1.57
            shR.x = step == 1 ? -1.5 : (step == 3 ? 0 : -0.8); elR.x = -1.57
            headR.y = step < 2 ? 0.5 : -0.5
        case .calma:
            shL.x = -1.0; shR.x = -1.0; elL.x = -0.3; elR.x = -0.3
            shL.z = -0.4 - sin(ct * 4) * 0.2; shR.z = 0.4 + sin(ct * 4) * 0.2
            spineR.x = 0.05
        case .sky:
            shL.z = -2.7; shR.z = 2.7; shL.x = -0.3; shR.x = -0.3; elL.x = 0; elR.x = 0
            headR.x = -0.6; spineR.x = -0.2
        case .griddy:
            let a = ct * 9
            hipL.x = -sin(a) * 0.8; kneeL.x = max(0, cos(a)) * 1.4
            hipR.x = sin(a) * 0.8; kneeR.x = max(0, -cos(a)) * 1.4
            shL.x = -1.2; shR.x = -1.2; elL.x = -1.6 + sin(a) * 0.3; elR.x = -1.6 - sin(a) * 0.3
            spineR.x = 0.25
        case .heart:
            shL.x = -1.6; shR.x = -1.6; shL.z = 0.5; shR.z = -0.5; elL.x = -1.2; elR.x = -1.2
            headR.x = -0.1
        }
    }
}


/// Celebration ids are persisted in profiles — append only.
enum Celebration: Int, CaseIterable, Codable {
    case siu, kneeSlide, airplane, backflip, shush, robot, calma, sky, griddy, heart
}
