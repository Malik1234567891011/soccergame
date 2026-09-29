import UIKit

enum FaceExpression: String { case neutral, blink, fierce, happy, shocked, hurt, flow }

/// Paints anime faces into the head's cylindrical UV space (u = angle around the head, face at u=0.5).
enum FaceTexture {
    static let size = CGSize(width: 1024, height: 512)
    // Model-derived scale: pixels per metre on the face surface.
    static let pxX: CGFloat = 975
    static let pxY: CGFloat = 1231
    static let eyeY: CGFloat = 286
    static let eyeDX: CGFloat = 66

    static var cache: [String: UIImage] = [:]

    static func image(_ a: Appearance, _ e: FaceExpression) -> UIImage {
        let key = "face-\(a.skinTone)-\(a.eyes)-\(a.eyeColor)-\(a.facialHair)-\(a.hairColor)-\(e.rawValue)"
        if let c = cache[key] { return c }
        let img = Tex.render(size) { c, s in draw(c, s, a, e, glowOnly: false) }
        cache[key] = img
        return img
    }

    /// Emission map: only the irises, so bloom makes the eyes flare in Flow.
    static func glow(_ a: Appearance) -> UIImage {
        Tex.render(size, key: "glow-\(a.eyeColor)-\(a.eyes)") { c, s in
            c.setFillColor(UIColor.black.cgColor); c.fill(CGRect(origin: .zero, size: s))
            let col = UIColor(hex: Appearance.eyeColors[a.eyeColor % Appearance.eyeColors.count])
            for side: CGFloat in [-1, 1] {
                let cx = s.width / 2 + side * eyeDX
                c.setFillColor(col.lighter(0.4).cgColor)
                c.fillEllipse(in: CGRect(x: cx - 20, y: eyeY - 30, width: 40, height: 60))
                c.setFillColor(UIColor.white.cgColor)
                c.fillEllipse(in: CGRect(x: cx - 8, y: eyeY - 14, width: 16, height: 28))
            }
        }
    }

    private static func draw(_ c: CGContext, _ s: CGSize, _ a: Appearance, _ e: FaceExpression, glowOnly: Bool) {
        let skin = a.skinColor
        c.setFillColor(skin.cgColor)
        c.fill(CGRect(origin: .zero, size: s))
        let ink = UIColor(red: 0.12, green: 0.07, blue: 0.08, alpha: 1)
        let iris = UIColor(hex: Appearance.eyeColors[a.eyeColor % Appearance.eyeColors.count])
        let cx = s.width / 2
        c.setLineCap(.round)
        c.setLineJoin(.round)

        // Soft cheek blush.
        c.setFillColor(UIColor(red: 1, green: 0.45, blue: 0.45, alpha: e == .happy ? 0.28 : 0.14).cgColor)
        for side: CGFloat in [-1, 1] {
            c.fillEllipse(in: CGRect(x: cx + side * 78 - 22, y: eyeY + 40, width: 44, height: 16))
        }

        // Facial hair (painted, anime-style).
        let fh = a.hairUIColor.darker(0.1)
        switch a.facialHair {
        case .none: break
        case .stubble:
            c.setFillColor(fh.withAlphaComponent(0.22).cgColor)
            let p = UIBezierPath()
            p.move(to: CGPoint(x: cx - 95, y: eyeY + 60))
            p.addQuadCurve(to: CGPoint(x: cx + 95, y: eyeY + 60), controlPoint: CGPoint(x: cx, y: eyeY + 250))
            p.addQuadCurve(to: CGPoint(x: cx - 95, y: eyeY + 60), controlPoint: CGPoint(x: cx, y: eyeY + 150))
            c.addPath(p.cgPath); c.fillPath()
        case .beard:
            c.setFillColor(fh.cgColor)
            let p = UIBezierPath()
            p.move(to: CGPoint(x: cx - 100, y: eyeY + 40))
            p.addQuadCurve(to: CGPoint(x: cx + 100, y: eyeY + 40), controlPoint: CGPoint(x: cx, y: eyeY + 270))
            p.addLine(to: CGPoint(x: cx + 60, y: eyeY + 75))
            p.addQuadCurve(to: CGPoint(x: cx - 60, y: eyeY + 75), controlPoint: CGPoint(x: cx, y: eyeY + 150))
            p.close()
            c.addPath(p.cgPath); c.fillPath()
        case .goatee:
            c.setFillColor(fh.cgColor)
            c.fillEllipse(in: CGRect(x: cx - 22, y: eyeY + 128, width: 44, height: 40))
        case .mustache:
            c.setFillColor(fh.cgColor)
            c.fillEllipse(in: CGRect(x: cx - 34, y: eyeY + 86, width: 68, height: 14))
        }

        // Nose: a tiny shadow tick.
        c.setStrokeColor(skin.darker(0.3).cgColor)
        c.setLineWidth(3)
        c.move(to: CGPoint(x: cx + 3, y: eyeY + 50)); c.addLine(to: CGPoint(x: cx - 2, y: eyeY + 62)); c.strokePath()

        // Mouth.
        c.setStrokeColor(ink.cgColor)
        c.setLineWidth(4.5)
        let my = eyeY + 104
        switch e {
        case .happy:
            let p = UIBezierPath()
            p.move(to: CGPoint(x: cx - 30, y: my - 6))
            p.addQuadCurve(to: CGPoint(x: cx + 30, y: my - 6), controlPoint: CGPoint(x: cx, y: my + 38))
            p.close()
            c.setFillColor(UIColor(red: 0.55, green: 0.12, blue: 0.15, alpha: 1).cgColor)
            c.addPath(p.cgPath); c.fillPath()
            c.setFillColor(UIColor(red: 1, green: 0.5, blue: 0.5, alpha: 1).cgColor)
            c.fillEllipse(in: CGRect(x: cx - 12, y: my + 6, width: 24, height: 10))
            c.setFillColor(UIColor.white.cgColor)
            c.fill(CGRect(x: cx - 22, y: my - 5, width: 44, height: 6))
            c.addPath(p.cgPath); c.strokePath()
        case .shocked, .hurt:
            c.setFillColor(UIColor(red: 0.45, green: 0.1, blue: 0.12, alpha: 1).cgColor)
            let r = CGRect(x: cx - 11, y: my - 4, width: 22, height: e == .shocked ? 26 : 12)
            c.fillEllipse(in: r); c.strokeEllipse(in: r)
        case .fierce, .flow:
            c.move(to: CGPoint(x: cx - 22, y: my + 2)); c.addQuadCurve(to: CGPoint(x: cx + 24, y: my - 6), control: CGPoint(x: cx + 4, y: my + 6))
            c.strokePath()
        default:
            c.move(to: CGPoint(x: cx - 16, y: my)); c.addQuadCurve(to: CGPoint(x: cx + 16, y: my), control: CGPoint(x: cx, y: my + 5))
            c.strokePath()
        }

        // Eyes.
        for side: CGFloat in [-1, 1] {
            let ex = cx + side * eyeDX
            drawEye(c, center: CGPoint(x: ex, y: eyeY), side: side, style: a.eyes, expr: e, iris: iris, ink: ink)
            // Brows.
            let hair = a.hairUIColor.darker(0.25)
            c.setStrokeColor(hair.cgColor)
            c.setLineWidth(9)
            var inner = CGPoint(x: ex - side * 26, y: eyeY - 62)
            var outer = CGPoint(x: ex + side * 30, y: eyeY - 70)
            switch e {
            case .fierce, .flow: inner.y += 14; outer.y -= 4
            case .happy: inner.y -= 6; outer.y -= 2
            case .shocked: inner.y -= 14; outer.y -= 12
            case .hurt: inner.y -= 12; outer.y += 6
            default: break
            }
            c.move(to: inner)
            c.addQuadCurve(to: outer, control: CGPoint(x: (inner.x + outer.x) / 2, y: min(inner.y, outer.y) - 8))
            c.strokePath()
        }
    }

    private static func drawEye(_ c: CGContext, center: CGPoint, side: CGFloat, style: EyeStyle, expr: FaceExpression, iris: UIColor, ink: UIColor) {
        var w: CGFloat = 64, h: CGFloat = 96
        switch style {
        case .round: break
        case .sharp: h = 76; w = 68
        case .sleepy: h = 72
        case .wide: h = 104; w = 68
        }
        let x = center.x, y = center.y
        if expr == .blink || expr == .happy || expr == .hurt {
            // Closed: happy arches ^ ^, blink/hurt flat lines.
            c.setStrokeColor(ink.cgColor)
            c.setLineWidth(7)
            if expr == .happy {
                c.move(to: CGPoint(x: x - w / 2, y: y + 8))
                c.addQuadCurve(to: CGPoint(x: x + w / 2, y: y + 8), control: CGPoint(x: x, y: y - 28))
            } else {
                c.move(to: CGPoint(x: x - w / 2, y: y + 6))
                c.addQuadCurve(to: CGPoint(x: x + w / 2, y: y + 4), control: CGPoint(x: x, y: y + (expr == .hurt ? -6 : 14)))
            }
            c.strokePath()
            return
        }
        let top = y - h / 2 + (style == .sleepy ? 12 : 0)
        let eyeRect = CGRect(x: x - w / 2, y: top, width: w, height: y + h / 2 - top)
        // Sclera.
        c.saveGState()
        let sclera = UIBezierPath(roundedRect: eyeRect, cornerRadius: w * 0.42)
        c.addPath(sclera.cgPath)
        c.setFillColor(UIColor(white: 0.98, alpha: 1).cgColor)
        c.fillPath()
        c.addPath(sclera.cgPath); c.clip()
        // Iris with vertical gradient.
        let iw: CGFloat = expr == .shocked ? w * 0.5 : w * 0.74
        let ih: CGFloat = expr == .shocked ? h * 0.55 : h * 0.86
        let irect = CGRect(x: x - iw / 2 - side * 2, y: y - ih / 2 + 6, width: iw, height: ih)
        let cs = CGColorSpaceCreateDeviceRGB()
        let g = CGGradient(colorsSpace: cs, colors: [iris.darker(0.55).cgColor, iris.cgColor, iris.lighter(0.35).cgColor] as CFArray, locations: [0, 0.55, 1])!
        c.saveGState()
        c.addEllipse(in: irect); c.clip()
        c.drawLinearGradient(g, start: CGPoint(x: x, y: irect.minY), end: CGPoint(x: x, y: irect.maxY), options: [])
        c.restoreGState()
        // Pupil.
        c.setFillColor(iris.darker(0.8).cgColor)
        let pw = iw * (expr == .shocked ? 0.3 : 0.42), ph = ih * 0.5
        c.fillEllipse(in: CGRect(x: irect.midX - pw / 2, y: irect.midY - ph / 2 - 2, width: pw, height: ph))
        // Upper-lid shadow.
        c.setFillColor(UIColor(red: 0.2, green: 0.1, blue: 0.2, alpha: 0.25).cgColor)
        c.fill(CGRect(x: eyeRect.minX, y: eyeRect.minY, width: w, height: 12))
        c.restoreGState()
        // Highlights.
        c.setFillColor(UIColor.white.cgColor)
        c.fillEllipse(in: CGRect(x: irect.minX + iw * 0.12, y: irect.minY + ih * 0.14, width: iw * 0.36, height: ih * 0.28))
        c.fillEllipse(in: CGRect(x: irect.maxX - iw * 0.32, y: irect.maxY - ih * 0.3, width: iw * 0.16, height: ih * 0.12))
        // Upper lash line with an outer flick.
        c.setStrokeColor(ink.cgColor)
        c.setLineWidth(8)
        let lashY = top + 2 + (expr == .fierce || expr == .flow ? 6 : 0)
        c.move(to: CGPoint(x: x - side * (w / 2 + 2), y: lashY + 10 + (expr == .fierce || expr == .flow ? -8 : 0)))
        c.addQuadCurve(to: CGPoint(x: x + side * (w / 2 + 8), y: lashY + 4), control: CGPoint(x: x, y: lashY - 10))
        c.strokePath()
        c.setLineWidth(5)
        c.move(to: CGPoint(x: x + side * (w / 2 + 6), y: lashY + 4))
        c.addLine(to: CGPoint(x: x + side * (w / 2 + 16), y: lashY - 4))
        c.strokePath()
        // Lower lash hint.
        c.setLineWidth(3)
        c.setStrokeColor(ink.withAlphaComponent(0.6).cgColor)
        c.move(to: CGPoint(x: x - w * 0.2, y: y + h / 2 + 2))
        c.addQuadCurve(to: CGPoint(x: x + side * w * 0.45, y: y + h / 2 - 6), control: CGPoint(x: x + side * w * 0.2, y: y + h / 2 + 4))
        c.strokePath()
    }
}

/// Kit printing in the shirt's cylindrical UV: back centred at u=0.25, left side u=0.5, front u=0.75.
enum KitTexture {
    static func shirt(_ a: Appearance, name: String) -> UIImage {
        let key = "kit-\(a.shirtPattern)-\(a.primary)-\(a.secondary)-\(a.number)-\(name)"
        return Tex.render(CGSize(width: 1024, height: 512), key: key) { c, s in
            let p = UIColor(hex: a.primary), q = UIColor(hex: a.secondary)
            c.setFillColor(p.cgColor); c.fill(CGRect(origin: .zero, size: s))
            c.setFillColor(q.cgColor)
            switch a.shirtPattern {
            case .plain:
                // Shoulder yoke + side panels keep plain kits from looking empty.
                c.setFillColor(p.darker(0.18).cgColor)
                c.fill(CGRect(x: 0, y: 0, width: s.width, height: 60))
                c.setFillColor(q.withAlphaComponent(0.85).cgColor)
                c.fill(CGRect(x: 500, y: 60, width: 24, height: 452))
                c.fill(CGRect(x: 0, y: 60, width: 12, height: 452)); c.fill(CGRect(x: 1012, y: 60, width: 12, height: 452))
            case .stripes:
                for i in stride(from: 0, to: 16, by: 2) { c.fill(CGRect(x: CGFloat(i) * 64 + 16, y: 0, width: 64, height: s.height)) }
            case .hoops:
                for i in stride(from: 0, to: 8, by: 2) { c.fill(CGRect(x: 0, y: CGFloat(i) * 64 + 60, width: s.width, height: 64)) }
            case .sash:
                // Diagonal across the front (u 0.5..1).
                c.move(to: CGPoint(x: 540, y: 40)); c.addLine(to: CGPoint(x: 640, y: 40)); c.addLine(to: CGPoint(x: 1010, y: 470)); c.addLine(to: CGPoint(x: 910, y: 470)); c.fillPath()
                c.move(to: CGPoint(x: 20, y: 40)); c.addLine(to: CGPoint(x: 120, y: 40)); c.addLine(to: CGPoint(x: 490, y: 470)); c.addLine(to: CGPoint(x: 390, y: 470)); c.fillPath()
            case .halves:
                c.fill(CGRect(x: 256, y: 0, width: 512, height: s.height))
            case .pinstripe:
                for i in 0..<48 { c.fill(CGRect(x: CGFloat(i) * 21.33 + 9, y: 0, width: 4, height: s.height)) }
            case .chevron:
                c.setLineWidth(40); c.setStrokeColor(q.cgColor)
                for base: CGFloat in [0, 512] {
                    c.move(to: CGPoint(x: base, y: 120)); c.addLine(to: CGPoint(x: base + 256, y: 230)); c.addLine(to: CGPoint(x: base + 512, y: 120)); c.strokePath()
                }
            case .gradient:
                let cs = CGColorSpaceCreateDeviceRGB()
                let g = CGGradient(colorsSpace: cs, colors: [p.cgColor, q.cgColor] as CFArray, locations: [0.15, 1])!
                c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: s.height), options: [])
            case .camo:
                var seed: UInt64 = 42
                for _ in 0..<90 {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    let x = CGFloat(seed % 1024), y = CGFloat((seed >> 12) % 512), r = CGFloat(20 + (seed >> 24) % 50)
                    c.setFillColor((seed >> 32) % 2 == 0 ? q.withAlphaComponent(0.85).cgColor : p.darker(0.35).cgColor)
                    c.fillEllipse(in: CGRect(x: x - r, y: y - r * 0.6, width: r * 2, height: r * 1.2))
                }
            case .checker:
                for i in 0..<16 { for j in 0..<8 where (i + j) % 2 == 0 { c.fill(CGRect(x: i * 64, y: j * 64, width: 64, height: 64)) } }
            }
            // Jagged "lightning" graphic accents on the front for energy (anime kit feel).
            if a.shirtPattern == .plain || a.shirtPattern == .gradient {
                c.setFillColor(q.withAlphaComponent(0.9).cgColor)
                let z = UIBezierPath()
                z.move(to: CGPoint(x: 820, y: 150)); z.addLine(to: CGPoint(x: 900, y: 240)); z.addLine(to: CGPoint(x: 860, y: 250))
                z.addLine(to: CGPoint(x: 940, y: 400)); z.addLine(to: CGPoint(x: 830, y: 270)); z.addLine(to: CGPoint(x: 870, y: 262)); z.close()
                c.addPath(z.cgPath); c.fillPath()
            }
            let numColor = [ShirtPattern.plain, .gradient, .camo].contains(a.shirtPattern) ? q : UIColor.white
            UIGraphicsPushContext(c)
            // Back: name + number.
            let num = NSAttributedString(string: "\(a.number)", attributes: [
                .font: UIFont.systemFont(ofSize: 200, weight: .black).rounded(), .foregroundColor: numColor,
                .strokeColor: p.darker(0.6), .strokeWidth: -3.5, .kern: -6,
            ])
            let ns = num.size()
            num.draw(at: CGPoint(x: 256 - ns.width / 2, y: 120))
            if !name.isEmpty {
                let nm = NSAttributedString(string: name.uppercased(), attributes: [
                    .font: UIFont.systemFont(ofSize: 40, weight: .heavy).rounded(), .foregroundColor: numColor, .kern: 3,
                    .strokeColor: p.darker(0.6), .strokeWidth: -3,
                ])
                let ms = nm.size()
                nm.draw(at: CGPoint(x: 256 - ms.width / 2, y: 78))
            }
            // Front: wordmark + small number + crest.
            let mark = NSAttributedString(string: "PANNA", attributes: [
                .font: UIFont.systemFont(ofSize: 52, weight: .black).rounded(), .foregroundColor: numColor, .kern: 2,
                .strokeColor: p.darker(0.6), .strokeWidth: -3,
            ])
            let mk = mark.size()
            mark.draw(at: CGPoint(x: 768 - mk.width / 2, y: 190))
            UIGraphicsPopContext()
            let crest = CGRect(x: 830, y: 96, width: 44, height: 52)
            let path = UIBezierPath()
            path.move(to: CGPoint(x: crest.minX, y: crest.minY)); path.addLine(to: CGPoint(x: crest.maxX, y: crest.minY))
            path.addLine(to: CGPoint(x: crest.maxX, y: crest.midY))
            path.addQuadCurve(to: CGPoint(x: crest.midX, y: crest.maxY), controlPoint: CGPoint(x: crest.maxX, y: crest.maxY - 6))
            path.addQuadCurve(to: CGPoint(x: crest.minX, y: crest.midY), controlPoint: CGPoint(x: crest.minX, y: crest.maxY - 6))
            path.close()
            c.setFillColor(q.cgColor); c.addPath(path.cgPath); c.fillPath()
            c.setFillColor(p.cgColor); c.fillEllipse(in: crest.insetBy(dx: 12, dy: 15))
            // Hem band.
            c.setFillColor(p.darker(0.25).cgColor)
            c.fill(CGRect(x: 0, y: 470, width: s.width, height: 42))
        }
    }

    static func shorts(_ a: Appearance) -> UIImage {
        Tex.render(CGSize(width: 512, height: 64), key: "shorts-\(a.shorts)-\(a.secondary)") { c, s in
            c.setFillColor(UIColor(hex: a.shorts).cgColor); c.fill(CGRect(origin: .zero, size: s))
            c.setFillColor(UIColor(hex: a.secondary).cgColor)
            c.fill(CGRect(x: 244, y: 0, width: 24, height: s.height))
            c.fill(CGRect(x: 0, y: 0, width: 12, height: s.height)); c.fill(CGRect(x: 500, y: 0, width: 12, height: s.height))
        }
    }
}
