import UIKit

/// Painted characters are all authored in one "code kit": red jersey, yellow trim, blue shorts, green socks.
/// This repaints those regions in a team's colours on the CPU (identical on every device), keeping the painted shading.
enum KitRecolor {
    struct Kit: Hashable { var primary: UInt32; var secondary: UInt32; var shorts: UInt32; var socks: UInt32 }

    /// Hues measured from each character's own code-kit sheet at bake time (<id>_kit.json).
    struct Calibration {
        var red: Float = 0.0, blue: Float = 0.63, green: Float = 0.37
        var skinHue: Float = 0.07, skinSat: Float = 0.4
        static let `default` = Calibration()
        static func load(_ d: Data) -> Calibration? {
            guard let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
            func pair(_ k: String) -> (Float, Float)? {
                guard let a = o[k] as? [Double], a.count == 2 else { return nil }
                return (Float(a[0]), Float(a[1]))
            }
            var c = Calibration()
            if let r = pair("red") { c.red = r.0 }
            if let b = pair("blue") { c.blue = b.0 }
            if let g = pair("green") { c.green = g.0 }
            if let s = pair("skin") { c.skinHue = s.0; c.skinSat = s.1 }
            return c
        }
        /// How far from the jersey hue still counts as jersey: tight when the skin is a saturated near-red.
        var redTolerance: Float {
            skinSat > 0.45 ? max(0.012, min(0.035, (skinHue - red) * 0.5)) : 0.035
        }
    }

    private static var cache: [String: UIImage] = [:]
    private static let lock = NSLock()

    static func image(_ src: UIImage, id: String, kit: Kit, mask: UIImage? = nil, cal: Calibration = .default, size: Int = 2048) -> UIImage {
        let key = "\(id)-\(kit.primary)-\(kit.secondary)-\(kit.shorts)-\(kit.socks)-\(size)"
        lock.lock(); if let c = cache[key] { lock.unlock(); return c }; lock.unlock()
        guard let out = recolor(src, kit: kit, mask: mask, cal: cal, size: size) else { return src }
        lock.lock(); cache[key] = out; lock.unlock()
        return out
    }

    private static func rgb(_ c: UInt32) -> (Float, Float, Float) {
        (Float((c >> 16) & 0xFF) / 255, Float((c >> 8) & 0xFF) / 255, Float(c & 0xFF) / 255)
    }

    @inline(__always) private static func smooth(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let t = min(1, max(0, (x - e0) / (e1 - e0)))
        return t * t * (3 - 2 * t)
    }

    static func recolor(_ src: UIImage, kit: Kit, mask: UIImage?, cal: Calibration, size: Int) -> UIImage? {
        guard let cg = src.cgImage else { return nil }
        let w = size, h = size
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Region mask (baked from the skeleton): 1 = clothing zone, 0 = head/hair/forearms/hands.
        var mbuf = [UInt8](repeating: 255, count: w * h)
        if let m = mask?.cgImage, let gctx = CGContext(data: &mbuf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) {
            gctx.draw(m, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        let tolR = cal.redTolerance
        let P = rgb(kit.primary), S = rgb(kit.secondary), B = rgb(kit.shorts), G = rgb(kit.socks)
        mbuf.withUnsafeBufferPointer { mp in
        buf.withUnsafeMutableBufferPointer { p in
            var i = 0
            let n = w * h * 4
            while i < n {
                let region = Float(mp[i / 4]) / 255
                let r = Float(p[i]) / 255, g = Float(p[i + 1]) / 255, b = Float(p[i + 2]) / 255
                let mx = max(r, g, b), mn = min(r, g, b)
                let d = mx - mn
                if region > 0.02 && d > 0.04 && mx > 0.06 {
                    let sat = d / mx
                    var hue: Float
                    if mx == r { hue = (g - b) / d; if hue < 0 { hue += 6 } }
                    else if mx == g { hue = (b - r) / d + 2 }
                    else { hue = (r - g) / d + 4 }
                    hue /= 6
                    let satW = smooth(0.3, 0.48, sat) * smooth(0.06, 0.16, mx) * region
                    let dh = abs(hue - (cal.red < 0 ? cal.red + 1 : cal.red))
                    let dRed = min(dh, 1 - dh)
                    // Pale pink highlights on the red jersey: skin never sits this close to pure red hue.
                    // Jersey hue comes from the character's own sheet; the tolerance tightens when skin is a saturated near-red.
                    let satR = max(satW, smooth(0.14, 0.28, sat) * smooth(0.06, 0.16, mx) * region * (1 - smooth(tolR * 0.5, tolR * 0.9, dRed)))
                    let wRed = (1 - smooth(tolR, tolR + 0.012, dRed)) * satR
                    let wYel = (1 - smooth(0.028, 0.042, abs(hue - 0.14))) * satW
                    // Blue shorts / green socks sit far from skin and hair hues, so faded paint is caught too.
                    let satC = smooth(0.1, 0.24, sat) * smooth(0.04, 0.1, mx) * region
                    let wBlu = (1 - smooth(0.1, 0.14, abs(hue - cal.blue))) * satC
                    let wGrn = (1 - smooth(0.13, 0.18, abs(hue - cal.green))) * satC
                    let shade = min(1.12, mx / 0.82)
                    var o = (r, g, b)
                    func mixIn(_ c: (Float, Float, Float), _ wt: Float, _ sh: Float) {
                        o = (o.0 + (c.0 * sh - o.0) * wt, o.1 + (c.1 * sh - o.1) * wt, o.2 + (c.2 * sh - o.2) * wt)
                    }
                    if wRed > 0 { mixIn(P, wRed, shade) }
                    // Bright orange = jersey red bleeding into the trim. Only where it cannot be this character's skin.
                    let skinClash = cal.skinSat > 0.45 ? (1 - smooth(0.015, 0.03, abs(hue - cal.skinHue))) : 0
                    let wOr = smooth(0.7, 0.8, sat) * smooth(0.5, 0.62, mx) * smooth(0.028, 0.04, hue) * (1 - smooth(0.095, 0.11, hue)) * (1 - skinClash) * region
                    if wOr > 0 {
                        let t = min(1, max(0, (hue - 0.03) / 0.08))
                        mixIn((P.0 + (S.0 - P.0) * t, P.1 + (S.1 - P.1) * t, P.2 + (S.2 - P.2) * t), wOr, shade)
                    }
                    // Purple = jersey red blending into shorts blue at the hem.
                    let wPu = smooth(0.35, 0.5, sat) * smooth(0.72, 0.76, hue) * (1 - smooth(0.9, 0.93, hue)) * smooth(0.08, 0.16, mx) * region
                    if wPu > 0 {
                        let t = min(1, max(0, (hue - 0.74) / 0.17))
                        mixIn((B.0 + (P.0 - B.0) * t, B.1 + (P.1 - B.1) * t, B.2 + (P.2 - B.2) * t), wPu, max(shade, 0.35))
                    }
                    if wYel > 0 { mixIn(S, wYel, shade) }
                    if wBlu > 0 { mixIn(B, wBlu, max(shade, 0.35)) }
                    if wGrn > 0 { mixIn(G, wGrn, shade) }
                    p[i] = UInt8(max(0, min(255, o.0 * 255)))
                    p[i + 1] = UInt8(max(0, min(255, o.1 * 255)))
                    p[i + 2] = UInt8(max(0, min(255, o.2 * 255)))
                }
                i += 4
            }
        }
        }
        guard let outCG = ctx.makeImage() else { return nil }
        return UIImage(cgImage: outCG)
    }

    /// Picks colours for two teams (and their keepers) that are always clearly different.
    static func distance(_ a: UInt32, _ b: UInt32) -> Float {
        let x = rgb(a), y = rgb(b)
        // Weighted RGB distance (rough perceptual).
        return ((x.0 - y.0) * (x.0 - y.0) * 2 + (x.1 - y.1) * (x.1 - y.1) * 4 + (x.2 - y.2) * (x.2 - y.2) * 3).squareRoot()
    }

    static let palette: [UInt32] = [0xFF3B5C, 0x3B8CFF, 0x39FF88, 0xFFD23B, 0xB26BFF, 0xFF8A3B, 0xFFFFFF, 0x16181F, 0x3BE8FF, 0xFF3BD4, 0x1E9E4A, 0x1B2A6B]

    static func farthest(from cs: [UInt32]) -> UInt32 {
        palette.max { a, b in cs.map { distance(a, $0) }.min()! < cs.map { distance(b, $0) }.min()! }!
    }
}
