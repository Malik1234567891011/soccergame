import UIKit

/// Painted characters are all authored in one "code kit": red jersey, yellow trim, blue shorts, green socks.
/// This repaints those regions in a team's colours on the CPU (identical on every device), keeping the painted shading.
enum KitRecolor {
    struct Kit: Hashable { var primary: UInt32; var secondary: UInt32; var shorts: UInt32; var socks: UInt32 }

    private static var cache: [String: UIImage] = [:]
    private static let lock = NSLock()

    static func image(_ src: UIImage, id: String, kit: Kit, mask: UIImage? = nil, size: Int = 2048) -> UIImage {
        let key = "\(id)-\(kit.primary)-\(kit.secondary)-\(kit.shorts)-\(kit.socks)-\(size)"
        lock.lock(); if let c = cache[key] { lock.unlock(); return c }; lock.unlock()
        guard let out = recolor(src, kit: kit, mask: mask, size: size) else { return src }
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

    static func recolor(_ src: UIImage, kit: Kit, mask: UIImage?, size: Int) -> UIImage? {
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
                    let dRed = min(hue, 1 - hue)
                    // Pale pink highlights on the red jersey: skin never sits this close to pure red hue.
                    let satR = max(satW, smooth(0.14, 0.28, sat) * smooth(0.06, 0.16, mx) * region * (1 - smooth(0.018, 0.03, dRed)))
                    let wRed = (1 - smooth(0.035, 0.06, dRed)) * satR
                    // Vivid orange = red jersey bleeding into yellow trim (skin is never this saturated).
                    let wOr = smooth(0.66, 0.76, sat) * smooth(0.035, 0.05, hue) * (1 - smooth(0.1, 0.115, hue)) * smooth(0.2, 0.3, mx) * region
                    let wYel = (1 - smooth(0.035, 0.06, abs(hue - 0.14))) * satW
                    // Blue shorts / green socks sit far from skin and hair hues, so faded paint is caught too.
                    let satC = smooth(0.1, 0.24, sat) * smooth(0.04, 0.1, mx) * region
                    let wBlu = (1 - smooth(0.1, 0.14, abs(hue - 0.63))) * satC
                    let wGrn = (1 - smooth(0.13, 0.18, abs(hue - 0.38))) * satC
                    let shade = min(1.12, mx / 0.82)
                    var o = (r, g, b)
                    func mixIn(_ c: (Float, Float, Float), _ wt: Float, _ sh: Float) {
                        o = (o.0 + (c.0 * sh - o.0) * wt, o.1 + (c.1 * sh - o.1) * wt, o.2 + (c.2 * sh - o.2) * wt)
                    }
                    if wRed > 0 { mixIn(P, wRed, shade) }
                    if wOr > 0 {
                        let t = min(1, max(0, (hue - 0.035) / 0.08))
                        mixIn((P.0 + (S.0 - P.0) * t, P.1 + (S.1 - P.1) * t, P.2 + (S.2 - P.2) * t), wOr, shade)
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
