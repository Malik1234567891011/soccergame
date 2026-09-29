import SwiftUI
import SceneKit
import PannaCore

/// A small lit stage that shows one or more footballers up close (locker, reveals, lineups).
final class CharacterStage: NSObject, SCNSceneRendererDelegate, ObservableObject {
    let scene = SCNScene()
    let camera = SCNNode()
    private(set) var rigs: [CharacterRig] = []
    private var holders: [SCNNode] = []
    private var last: TimeInterval = 0
    private var t: Float = 0
    var spin: Float = 0.35
    var animation: PoseInput.Kind = .idle
    var turntable = true
    var yaw: Float = 0

    init(background: UIColor = UIColor(hex: 0x0B0D18), floorColor: UIColor = UIColor(hex: 0x151827), floor: Bool = true) {
        super.init()
        scene.background.contents = background
        let cam = SCNCamera()
        cam.fieldOfView = 26
        cam.wantsHDR = ProcessInfo.processInfo.environment["PANNA_NOHDR"] == nil
        cam.bloomIntensity = 0.6
        cam.bloomThreshold = 1.2
        cam.wantsExposureAdaptation = false
        cam.vignettingIntensity = 0.4
        camera.camera = cam
        camera.position = SCNVector3(0, 1.15, 6.4)
        camera.look(at: SCNVector3(0, 0.88, 0))
        scene.rootNode.addChildNode(camera)
        // Floor disc with a glow ring.
        let disc = SCNCylinder(radius: 1.1, height: 0.04)
        disc.materials = [Mat.pbr(floorColor, rough: 0.6, rim: 0)]
        let dn = SCNNode(geometry: disc)
        dn.position.y = -0.02
        if floor { scene.rootNode.addChildNode(dn) }
        let ring = Geo.node(Geo.ring(inner: 1.05, outer: 1.12), Mat.emissive(UIColor(hex: 0x39FF88), intensity: 1.6))
        ring.position.y = 0.005
        if floor { scene.rootNode.addChildNode(ring) }
        let amb = SCNLight(); amb.type = .ambient; amb.intensity = 400
        let an = SCNNode(); an.light = amb; scene.rootNode.addChildNode(an)
        let key = SCNLight(); key.type = .directional; key.intensity = 1200; key.castsShadow = true
        key.shadowMode = .deferred; key.shadowColor = UIColor(white: 0, alpha: 0.5); key.shadowRadius = 6
        let kn = SCNNode(); kn.light = key; kn.position = SCNVector3(-2, 5, 4); kn.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(kn)
    }

    func setCharacters(_ looks: [(Appearance, String)], spacing: Float = 1.25) {
        setCharacters(looks.map { ($0.0, $0.1, nil) }, spacing: spacing)
    }

    func setCharacters(_ looks: [(Appearance, String, String?)], spacing: Float = 1.25) {
        holders.forEach { $0.removeFromParentNode() }
        holders = []; rigs = []
        let n = Float(looks.count)
        for (i, l) in looks.enumerated() {
            let rig = CharacterRig(appearance: l.0, name: l.1, modelName: l.2)
            let h = SCNNode()
            h.position = SCNVector3((Float(i) - (n - 1) / 2) * spacing, 0, 0)
            h.addChildNode(rig.root)
            scene.rootNode.addChildNode(h)
            rigs.append(rig); holders.append(h)
        }
        if let z = ProcessInfo.processInfo.environment["PANNA_ZOOM"], let f = Float(z) {
            camera.position = SCNVector3(0, 1.45, f)
            camera.look(at: SCNVector3(0, 1.35, 0))
            return
        }
        if looks.count > 1 {
            let d = spacing < 1 ? 1.2 + n * spacing * 1.05 : 4.2 + n * 1.3
            camera.position = SCNVector3(0, spacing < 1 ? 1.5 : 1.3, d)
            camera.look(at: SCNVector3(0, spacing < 1 ? 1.35 : 0.95, 0))
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        if last == 0 { last = time }
        let dt = Float(min(0.05, time - last))
        last = time
        t += dt
        for (i, r) in rigs.enumerated() {
            var p = PoseInput()
            p.time = t + Float(i)
            switch animation {
            case .idle: break
            case .run:
                p.speed = 6; p.runPhase = t * 6
            case .celebrate:
                p.action = .celebrate; p.actionT = t.truncatingRemainder(dividingBy: 3.5); p.actionDur = 99; p.celebration = i % Celebration.allCases.count
            case .kick:
                let c = t.truncatingRemainder(dividingBy: 1.6)
                if c < 0.4 { p.action = .kick; p.actionT = c; p.actionDur = 0.4 }
            }
            r.pose(p, dt: dt)
            if turntable { holders[i].eulerAngles.y = sin(t * spin) * 0.5 + yaw } else { holders[i].eulerAngles.y = yaw }
        }
    }
}

extension PoseInput {
    enum Kind { case idle, run, celebrate, kick }
}

struct StageView: UIViewRepresentable {
    let stage: CharacterStage
    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = stage.scene
        v.pointOfView = stage.camera
        v.delegate = stage
        v.isPlaying = true
        v.rendersContinuously = true
        v.antialiasingMode = .multisampling4X
        v.backgroundColor = .clear
        return v
    }
    func updateUIView(_ uiView: SCNView, context: Context) {}
}
