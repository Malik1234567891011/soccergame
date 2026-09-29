import SceneKit
import UIKit

enum Mat {
    /// Fresnel rim light — makes vinyl figures pop against night arenas.
    static let rimModifier = """
    #pragma arguments
    float rimStrength;
    float3 rimColor;
    #pragma body
    float ndv = saturate(dot(_surface.normal, _surface.view));
    float rim = pow(1.0 - ndv, 3.0) * rimStrength;
    _surface.emission.rgb += rimColor * rim;
    """

    static func pbr(_ color: UIColor, rough: CGFloat = 0.5, metal: CGFloat = 0, rim: CGFloat = 0.55,
                    rimColor: UIColor = UIColor(white: 1, alpha: 1), emission: UIColor? = nil) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = rough
        m.metalness.contents = metal
        if let e = emission { m.emission.contents = e }
        if rim > 0 {
            m.shaderModifiers = [.surface: rimModifier]
            m.setValue(NSNumber(value: Float(rim)), forKey: "rimStrength")
            var c: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            rimColor.getRed(&c, green: &g, blue: &b, alpha: &a)
            m.setValue(NSValue(scnVector3: SCNVector3(Float(c), Float(g), Float(b))), forKey: "rimColor")
        }
        return m
    }

    static func textured(_ image: UIImage, rough: CGFloat = 0.6, metal: CGFloat = 0, rim: CGFloat = 0.5) -> SCNMaterial {
        let m = pbr(.white, rough: rough, metal: metal, rim: rim)
        m.diffuse.contents = image
        m.diffuse.mipFilter = .linear
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
        return m
    }

    static func unlit(_ color: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color
        return m
    }

    static func emissive(_ color: UIColor, intensity: CGFloat = 1) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor.black
        m.emission.contents = color
        m.emission.intensity = intensity
        return m
    }
}

// MARK: - Procedural textures

enum Tex {
    static var cache: [String: UIImage] = [:]

    static func render(_ size: CGSize, key: String? = nil, _ draw: (CGContext, CGSize) -> Void) -> UIImage {
        if let k = key, let c = cache[k] { return c }
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = false
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in draw(ctx.cgContext, size) }
        if let k = key { cache[k] = img }
        return img
    }

    /// Shirt panel. `back` panels carry the number; fronts get a crest.
    static func shirt(_ a: Appearance, back: Bool, name: String = "") -> UIImage {
        let key = "shirt-\(a.shirtPattern)-\(a.primary)-\(a.secondary)-\(back ? a.number : -1)-\(back ? name : "")"
        return render(CGSize(width: 256, height: 256), key: key) { c, s in
            let p = UIColor(hex: a.primary), q = UIColor(hex: a.secondary)
            c.setFillColor(p.cgColor); c.fill(CGRect(origin: .zero, size: s))
            c.setFillColor(q.cgColor)
            switch a.shirtPattern {
            case .plain:
                c.setFillColor(q.withAlphaComponent(0.9).cgColor)
                c.fill(CGRect(x: 0, y: 0, width: s.width, height: 18))
            case .stripes:
                for i in stride(from: 0, to: 8, by: 2) { c.fill(CGRect(x: CGFloat(i) * 32, y: 0, width: 32, height: s.height)) }
            case .hoops:
                for i in stride(from: 0, to: 8, by: 2) { c.fill(CGRect(x: 0, y: CGFloat(i) * 32 + 16, width: s.width, height: 32)) }
            case .sash:
                c.move(to: CGPoint(x: -20, y: 40)); c.addLine(to: CGPoint(x: 40, y: -20)); c.addLine(to: CGPoint(x: 290, y: 230)); c.addLine(to: CGPoint(x: 230, y: 290)); c.fillPath()
            case .halves:
                c.fill(CGRect(x: s.width / 2, y: 0, width: s.width / 2, height: s.height))
            case .pinstripe:
                for i in 0..<16 { c.fill(CGRect(x: CGFloat(i) * 16 + 7, y: 0, width: 3, height: s.height)) }
            case .chevron:
                c.setLineWidth(22); c.setStrokeColor(q.cgColor)
                c.move(to: CGPoint(x: 0, y: 70)); c.addLine(to: CGPoint(x: 128, y: 150)); c.addLine(to: CGPoint(x: 256, y: 70)); c.strokePath()
            case .gradient:
                let cs = CGColorSpaceCreateDeviceRGB()
                if let g = CGGradient(colorsSpace: cs, colors: [p.cgColor, q.cgColor] as CFArray, locations: [0.2, 1]) {
                    c.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 256), options: [])
                }
            case .camo:
                var rng = SystemRandomNumberGenerator()
                _ = rng
                var seed: UInt64 = 42
                for _ in 0..<40 {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    let x = CGFloat(seed % 256), y = CGFloat((seed >> 8) % 256), r = CGFloat(10 + (seed >> 16) % 30)
                    c.setFillColor((seed >> 24) % 2 == 0 ? q.withAlphaComponent(0.8).cgColor : p.darker(0.35).cgColor)
                    c.fillEllipse(in: CGRect(x: x - r, y: y - r * 0.6, width: r * 2, height: r * 1.2))
                }
            case .checker:
                for i in 0..<8 { for j in 0..<8 where (i + j) % 2 == 0 { c.fill(CGRect(x: i * 32, y: j * 32, width: 32, height: 32)) } }
            }
            // Collar trim.
            c.setFillColor(q.cgColor)
            c.fill(CGRect(x: 0, y: 0, width: s.width, height: 10))
            if back {
                let numColor = a.shirtPattern == .plain || a.shirtPattern == .gradient ? q : UIColor.white
                let str = NSAttributedString(string: "\(a.number)", attributes: [
                    .font: UIFont.systemFont(ofSize: 120, weight: .black).rounded(),
                    .foregroundColor: numColor,
                    .strokeColor: p.darker(0.5), .strokeWidth: -4,
                ])
                let sz = str.size()
                UIGraphicsPushContext(c)
                str.draw(at: CGPoint(x: (s.width - sz.width) / 2, y: 90))
                if !name.isEmpty {
                    let n = NSAttributedString(string: name.uppercased(), attributes: [
                        .font: UIFont.systemFont(ofSize: 30, weight: .heavy),
                        .foregroundColor: numColor, .kern: 2,
                    ])
                    let ns = n.size()
                    n.draw(at: CGPoint(x: (s.width - ns.width) / 2, y: 48))
                }
                UIGraphicsPopContext()
            } else {
                // Crest.
                c.setFillColor(q.cgColor)
                let crest = CGRect(x: 150, y: 50, width: 40, height: 46)
                let path = UIBezierPath()
                path.move(to: CGPoint(x: crest.minX, y: crest.minY))
                path.addLine(to: CGPoint(x: crest.maxX, y: crest.minY))
                path.addLine(to: CGPoint(x: crest.maxX, y: crest.midY))
                path.addQuadCurve(to: CGPoint(x: crest.midX, y: crest.maxY), controlPoint: CGPoint(x: crest.maxX, y: crest.maxY - 6))
                path.addQuadCurve(to: CGPoint(x: crest.minX, y: crest.midY), controlPoint: CGPoint(x: crest.minX, y: crest.maxY - 6))
                path.close()
                c.addPath(path.cgPath); c.fillPath()
                c.setFillColor(p.cgColor)
                c.fillEllipse(in: crest.insetBy(dx: 12, dy: 14))
                // Small sponsor bar.
                c.setFillColor(q.withAlphaComponent(0.85).cgColor)
                c.fill(CGRect(x: 58, y: 130, width: 140, height: 22))
            }
        }
    }

    static func noise(_ size: Int, seed: UInt64, base: UIColor, variance: CGFloat) -> UIImage {
        render(CGSize(width: size, height: size), key: "noise-\(size)-\(seed)-\(base.hexValue)") { c, s in
            c.setFillColor(base.cgColor); c.fill(CGRect(origin: .zero, size: s))
            var st = seed
            for _ in 0..<(size * size / 6) {
                st = st &* 6364136223846793005 &+ 1442695040888963407
                let x = CGFloat(st % UInt64(size)), y = CGFloat((st >> 16) % UInt64(size))
                let v = CGFloat((st >> 32) % 1000) / 1000 * 2 - 1
                c.setFillColor(v > 0 ? UIColor.white.withAlphaComponent(v * variance).cgColor : UIColor.black.withAlphaComponent(-v * variance).cgColor)
                c.fill(CGRect(x: x, y: y, width: 2, height: 2))
            }
        }
    }
}

extension UIFont {
    func rounded() -> UIFont {
        guard let d = fontDescriptor.withDesign(.rounded) else { return self }
        return UIFont(descriptor: d, size: pointSize)
    }
}
