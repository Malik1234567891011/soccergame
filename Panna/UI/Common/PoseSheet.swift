import SceneKit
import UIKit
import PannaCore

/// QA tool: renders every animation of a character frame-by-frame into contact sheets (Documents/poses/*.jpg).
/// Launch with PANNA_POSESHEET=<model id or "classic">.
enum PoseSheet {
    struct Clip { let name: String; let frames: [PoseInput] }

    static func clips() -> [Clip] {
        func seq(_ n: Int, _ make: (Float) -> PoseInput) -> [PoseInput] { (0..<n).map { make(Float($0) / Float(max(1, n - 1))) } }
        var out: [Clip] = []
        out.append(Clip(name: "idle", frames: seq(4) { f in var p = PoseInput(); p.time = f * 2; return p }))
        out.append(Clip(name: "run", frames: seq(8) { f in var p = PoseInput(); p.speed = 6; p.runPhase = f * 1.7; return p }))
        out.append(Clip(name: "sprint", frames: seq(8) { f in var p = PoseInput(); p.speed = 8; p.sprint = true; p.runPhase = f * 2.1; return p }))
        out.append(Clip(name: "dribble", frames: seq(6) { f in var p = PoseInput(); p.speed = 5; p.hasBall = true; p.runPhase = f * 1.7; return p }))
        out.append(Clip(name: "charge", frames: seq(4) { f in var p = PoseInput(); p.charge = f; return p }))
        out.append(Clip(name: "kick", frames: seq(8) { f in var p = PoseInput(); p.action = .kick; p.actionT = f * 0.32; p.actionDur = 0.32; return p }))
        out.append(Clip(name: "loftedpass", frames: seq(6) { f in var p = PoseInput(); p.action = .kick; p.variant = 1; p.actionT = f * 0.35; p.actionDur = 0.35; return p }))
        out.append(Clip(name: "bicycle", frames: seq(8) { f in var p = PoseInput(); p.action = .kick; p.variant = 2; p.actionT = f * 0.7; p.actionDur = 0.7; return p }))
        out.append(Clip(name: "header", frames: seq(6) { f in var p = PoseInput(); p.action = .header; p.actionT = f * 0.45; p.actionDur = 0.45; p.height = sin(f * .pi) * 0.5; return p }))
        out.append(Clip(name: "tackle", frames: seq(6) { f in var p = PoseInput(); p.action = .tackle; p.actionT = f * 0.42; p.actionDur = 0.42; return p }))
        out.append(Clip(name: "slide", frames: seq(6) { f in var p = PoseInput(); p.action = .slide; p.actionT = f * 0.62; p.actionDur = 0.62; return p }))
        for v in 0..<6 {
            out.append(Clip(name: "skill\(v)", frames: seq(6) { f in var p = PoseInput(); p.action = .skill; p.variant = UInt8(v); p.actionT = f * 0.42; p.actionDur = 0.42; p.localDir = V2(1, 0); return p }))
        }
        out.append(Clip(name: "stumble", frames: seq(4) { f in var p = PoseInput(); p.action = .stumble; p.actionT = f * 0.5; p.actionDur = 0.5; return p }))
        out.append(Clip(name: "ankles", frames: seq(4) { f in var p = PoseInput(); p.action = .ankles; p.actionT = f * 1.0; p.actionDur = 1.0; return p }))
        out.append(Clip(name: "knockdown", frames: seq(4) { f in var p = PoseInput(); p.action = .knockdown; p.actionT = f * 0.7; p.actionDur = 0.7; return p }))
        out.append(Clip(name: "dive", frames: seq(6) { f in var p = PoseInput(); p.action = .dive; p.isKeeper = true; p.actionT = f * 0.9; p.actionDur = 0.9; p.localDir = V2(1, 0); p.height = sin(min(f * 0.9 / 0.45, 1) * .pi) * 0.7; return p }))
        for c in Celebration.allCases {
            out.append(Clip(name: "celebrate_\(c)", frames: seq(8) { f in var p = PoseInput(); p.action = .celebrate; p.celebration = c.rawValue; p.actionT = 0.2 + f * 2.6; p.actionDur = 99; return p }))
        }
        return out
    }

    /// Every character: face close-up + full body idle + run frame, in two team kits. Documents/poses/roster_*.jpg
    static func roster() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let renderer = SCNRenderer(device: device, options: nil)
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("poses")
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ids: [(String, Bool)] = Catalog.prospects.map { ($0.id, true) } + Catalog.looks.map { ($0, false) }
        let kits: [(UInt32, UInt32, UInt32)] = [(0x3B8CFF, 0xFFFFFF, 0x1B2A6B), (0xFFD23B, 0x16181F, 0x16181F)]
        let cell = CGSize(width: 240, height: 300)
        for (ki, kit) in kits.enumerated() {
            for page in stride(from: 0, to: ids.count, by: 7) {
                let chunk = Array(ids[page..<min(ids.count, page + 7)])
                var images: [UIImage] = []
                for shot in 0..<3 {
                    for (id, isProspect) in chunk {
                        var a = isProspect ? Catalog.prospect(id)!.appearance : Appearance()
                        if !isProspect { a.look = id }
                        a.primary = kit.0; a.secondary = kit.1; a.shorts = kit.2; a.socks = kit.0
                        let scene = SCNScene()
                        scene.background.contents = UIColor(hex: 0x1A1D2E)
                        let rig = CharacterRig(appearance: a, name: id, modelName: isProspect ? id : nil)
                        let holder = SCNNode(); holder.addChildNode(rig.root)
                        holder.eulerAngles.y = shot == 0 ? 0.25 : (shot == 1 ? 0.7 : 1.4)
                        scene.rootNode.addChildNode(holder)
                        var p = PoseInput()
                        if shot == 2 { p.speed = 7; p.runPhase = 0.6; p.sprint = true }
                        for _ in 0..<40 { rig.pose(p, dt: 1.0 / 30) }
                        let cam = SCNNode(); cam.camera = SCNCamera()
                        if shot == 0 { cam.camera?.fieldOfView = 16; cam.position = SCNVector3(0, 1.72, 2.6); cam.look(at: SCNVector3(0, 1.62, 0)) }
                        else { cam.camera?.fieldOfView = 34; cam.position = SCNVector3(0, 1.1, 4.2); cam.look(at: SCNVector3(0, 0.92, 0)) }
                        scene.rootNode.addChildNode(cam)
                        let amb = SCNNode(); amb.light = SCNLight(); amb.light?.type = .ambient; amb.light?.intensity = 900
                        scene.rootNode.addChildNode(amb)
                        renderer.scene = scene; renderer.pointOfView = cam
                        images.append(renderer.snapshot(atTime: 0, with: cell, antialiasingMode: .multisampling4X))
                    }
                }
                let cols = chunk.count
                let sheet = UIGraphicsImageRenderer(size: CGSize(width: cell.width * CGFloat(cols), height: cell.height * 3)).image { _ in
                    for (i, img) in images.enumerated() { img.draw(at: CGPoint(x: CGFloat(i % cols) * cell.width, y: CGFloat(i / cols) * cell.height)) }
                    for (i, c) in chunk.enumerated() {
                        NSAttributedString(string: c.0, attributes: [.font: UIFont.boldSystemFont(ofSize: 18), .foregroundColor: UIColor.yellow])
                            .draw(at: CGPoint(x: CGFloat(i) * cell.width + 6, y: 4))
                    }
                }
                try? sheet.jpegData(compressionQuality: 0.85)?.write(to: dir.appendingPathComponent("roster_k\(ki)_\(page / 7).jpg"))
            }
        }
        print("[posesheet] done")
    }

    static func run(model: String) {
        if model == "roster" { roster(); return }
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let renderer = SCNRenderer(device: device, options: nil)
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("poses")
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var look = Appearance()
        if model == "classic" { look.hairStyle = .spikes } else if model.hasPrefix("l") { look.look = model; look.primary = 0xFF3B5C; look.secondary = 0xFFFFFF; look.shorts = 0x16181F; look.socks = 0xFF3B5C }
        let modelName: String? = (model == "classic" || model.hasPrefix("l")) ? nil : model
        let cell = CGSize(width: 260, height: 300)
        for clip in clips() {
            // Two angles per clip: 3/4 front and side.
            var images: [UIImage] = []
            for yaw in [Float(0.6), Float(1.57)] {
                for pose in clip.frames {
                    let scene = SCNScene()
                    scene.background.contents = UIColor(hex: 0x1A1D2E)
                    let rig = CharacterRig(appearance: look, isKeeper: false, name: "QA", modelName: modelName)
                    let holder = SCNNode(); holder.addChildNode(rig.root); holder.eulerAngles.y = yaw
                    scene.rootNode.addChildNode(holder)
                    // Settle smoothing by posing repeatedly.
                    for _ in 0..<40 { rig.pose(pose, dt: 1.0 / 30) }
                    let floor = SCNNode(geometry: SCNCylinder(radius: 0.9, height: 0.01)); floor.geometry?.firstMaterial?.diffuse.contents = UIColor(white: 0.25, alpha: 1)
                    scene.rootNode.addChildNode(floor)
                    let cam = SCNNode(); cam.camera = SCNCamera(); cam.camera?.fieldOfView = 34
                    cam.position = SCNVector3(0, 1.1, 4.4); cam.look(at: SCNVector3(0, 0.9, 0))
                    scene.rootNode.addChildNode(cam)
                    let amb = SCNNode(); amb.light = SCNLight(); amb.light?.type = .ambient; amb.light?.intensity = 900
                    scene.rootNode.addChildNode(amb)
                    renderer.scene = scene
                    renderer.pointOfView = cam
                    images.append(renderer.snapshot(atTime: 0, with: cell, antialiasingMode: .multisampling4X))
                }
            }
            let cols = clip.frames.count
            let sheet = UIGraphicsImageRenderer(size: CGSize(width: cell.width * CGFloat(cols), height: cell.height * 2)).image { ctx in
                for (i, img) in images.enumerated() {
                    img.draw(at: CGPoint(x: CGFloat(i % cols) * cell.width, y: CGFloat(i / cols) * cell.height))
                }
                let label = NSAttributedString(string: clip.name, attributes: [.font: UIFont.boldSystemFont(ofSize: 22), .foregroundColor: UIColor.yellow])
                label.draw(at: CGPoint(x: 8, y: 6))
            }
            try? sheet.jpegData(compressionQuality: 0.8)?.write(to: dir.appendingPathComponent(clip.name + ".jpg"))
        }
        print("[posesheet] done")
    }
}
