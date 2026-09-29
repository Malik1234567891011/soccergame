import SceneKit
import UIKit

/// Anime cel shading: hard light terminator, tinted shadows, crisp rim, small specular pop.
/// Characters use a fixed "key light" so they always read clean regardless of the venue's lights.
enum Toon {
    static let surface = """
    #pragma arguments
    float3 lightDir;
    float3 shadowTint;
    float rimAmount;
    float3 rimColor;
    float specAmount;
    #pragma body
    float3 N = normalize(_surface.normal);
    float3 L = normalize((scn_frame.viewTransform * float4(lightDir, 0.0)).xyz);
    float3 V = normalize(_surface.view);
    float ndl = dot(N, L);
    float lit = smoothstep(-0.03, 0.04, ndl);
    float3 base = _surface.diffuse.rgb;
    float3 col = mix(base * shadowTint, base, lit);
    float fres = 1.0 - saturate(dot(N, V));
    col += rimColor * smoothstep(0.58, 0.66, fres) * rimAmount * (0.35 + 0.65 * lit);
    float3 H = normalize(L + V);
    col += smoothstep(0.955, 0.97, dot(N, H)) * specAmount * lit;
    _surface.diffuse = float4(col, _surface.diffuse.a);
    """

    /// Painted characters wear a colour-coded kit (red jersey, yellow trim, blue shorts, green socks).
    /// This remaps those hues to the player's kit while keeping the painted shading and line art.
    static let kitSurface = """
    #pragma arguments
    float3 lightDir;
    float3 shadowTint;
    float rimAmount;
    float3 rimColor;
    float specAmount;
    float3 kitPrimary;
    float3 kitSecondary;
    float3 kitShorts;
    float3 kitSocks;
    #pragma body
    float3 src = _surface.diffuse.rgb;
    // Classify in gamma space (textures arrive linearised), tint in linear space.
    float3 gm = pow(max(src, float3(0.0)), float3(1.0 / 2.2));
    float mx = max(gm.r, max(gm.g, gm.b));
    float mn = min(gm.r, min(gm.g, gm.b));
    float sat = (mx - mn) / max(mx, 0.0001);
    float hue = 0.0;
    if (mx - mn > 0.0001) {
        if (mx == gm.r) hue = fmod((gm.g - gm.b) / (mx - mn), 6.0);
        else if (mx == gm.g) hue = (gm.b - gm.r) / (mx - mn) + 2.0;
        else hue = (gm.r - gm.g) / (mx - mn) + 4.0;
        hue = hue / 6.0;
        if (hue < 0.0) hue += 1.0;
    }
    float satW = smoothstep(0.42, 0.6, sat) * smoothstep(0.1, 0.22, mx);
    float dRed = min(hue, 1.0 - hue);
    float wRed = (1.0 - smoothstep(0.02, 0.04, dRed)) * satW;
    float wYel = (1.0 - smoothstep(0.035, 0.06, abs(hue - 0.14))) * satW;
    float wBlu = (1.0 - smoothstep(0.07, 0.11, abs(hue - 0.63))) * satW;
    float wGrn = (1.0 - smoothstep(0.08, 0.12, abs(hue - 0.37))) * satW;
    float shadeG = clamp(mx / 0.82, 0.0, 1.12);
    float shade = pow(shadeG, 2.2);
    float3 tinted = src;
    tinted = mix(tinted, kitPrimary * shade, wRed);
    tinted = mix(tinted, kitSecondary * shade, wYel);
    tinted = mix(tinted, kitShorts * max(shade, 0.35) + float3(0.012) * shade, wBlu);
    tinted = mix(tinted, kitSocks * shade, wGrn);
    _surface.diffuse = float4(tinted, _surface.diffuse.a);
    """ + surface.components(separatedBy: "#pragma body")[1]

    struct Kit { var primary: UIColor; var secondary: UIColor; var shorts: UIColor; var socks: UIColor }

    static func paintedMaterial(texture: UIImage?, kit: Kit?, shadow: SIMD3<Float>) -> SCNMaterial {
        let m = material(.white, texture: texture, spec: 0, rim: 0.35, shadow: shadow)
        guard let k = kit else { return m }
        let args = m.shaderModifiers?[.surface]
        _ = args
        m.shaderModifiers = [.surface: kitSurface]
        func v(_ c: UIColor) -> NSValue {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            // sRGB → linear so the tint matches the texture's colour space.
            func lin(_ x: CGFloat) -> Float { Float(x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)) }
            return NSValue(scnVector3: SCNVector3(lin(r), lin(g), lin(b)))
        }
        m.setValue(v(k.primary), forKey: "kitPrimary")
        m.setValue(v(k.secondary), forKey: "kitSecondary")
        m.setValue(v(k.shorts), forKey: "kitShorts")
        m.setValue(v(k.socks), forKey: "kitSocks")
        return m
    }

    /// Inverted-hull outline: push along the normal (scaled with distance so it stays ~1pt on screen).
    static let outlineGeometry = """
    #pragma arguments
    float outlineWidth;
    #pragma body
    float4 vp = scn_node.modelViewTransform * _geometry.position;
    float w = outlineWidth * clamp(-vp.z * 0.075, 1.0, 3.2);
    _geometry.position.xyz += _geometry.normal * w;
    """

    struct Style {
        var lightDir = SIMD3<Float>(-0.35, 0.85, 0.55)
        var shadowTint = SIMD3<Float>(0.62, 0.6, 0.78)
        var rimColor = SIMD3<Float>(1, 0.95, 0.9)
        var rimAmount: Float = 0.45
        var outline = UIColor(red: 0.08, green: 0.06, blue: 0.1, alpha: 1)
        static let standard = Style()
    }

    static var style = Style.standard

    static func material(_ color: UIColor, texture: UIImage? = nil, spec: Float = 0.15, rim: Float? = nil, emission: UIColor? = nil, shadow: SIMD3<Float>? = nil) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = texture ?? color
        if texture != nil {
            m.diffuse.wrapS = .repeat
            m.diffuse.wrapT = .repeat
            m.diffuse.mipFilter = .linear
        }
        if let e = emission { m.emission.contents = e }
        m.shaderModifiers = [.surface: surface]
        let st = style
        m.setValue(NSValue(scnVector3: SCNVector3(st.lightDir.x, st.lightDir.y, st.lightDir.z)), forKey: "lightDir")
        let sh = shadow ?? st.shadowTint
        m.setValue(NSValue(scnVector3: SCNVector3(sh.x, sh.y, sh.z)), forKey: "shadowTint")
        m.setValue(NSValue(scnVector3: SCNVector3(st.rimColor.x, st.rimColor.y, st.rimColor.z)), forKey: "rimColor")
        m.setValue(NSNumber(value: rim ?? st.rimAmount), forKey: "rimAmount")
        m.setValue(NSNumber(value: spec), forKey: "specAmount")
        return m
    }

    static func outlineMaterial(width: Float = 0.016, color: UIColor? = nil) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color ?? style.outline
        m.cullMode = .front
        m.shaderModifiers = [.geometry: outlineGeometry]
        m.setValue(NSNumber(value: width), forKey: "outlineWidth")
        return m
    }

    /// Vertical gradient with an "angel ring" highlight band — classic anime hair.
    static func hairTexture(_ c: UIColor) -> UIImage {
        Tex.render(CGSize(width: 8, height: 256), key: "hair-\(c.hexValue)") { ctx, s in
            let cs = CGColorSpaceCreateDeviceRGB()
            let top = c.lighter(0.12), bottom = c.darker(0.28)
            let g = CGGradient(colorsSpace: cs, colors: [top.cgColor, c.cgColor, bottom.cgColor] as CFArray, locations: [0, 0.45, 1])!
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: s.height), options: [])
            ctx.setFillColor(c.lighter(0.55).withAlphaComponent(0.8).cgColor)
            ctx.fill(CGRect(x: 0, y: 70, width: s.width, height: 10))
            ctx.setFillColor(c.lighter(0.35).withAlphaComponent(0.5).cgColor)
            ctx.fill(CGRect(x: 0, y: 82, width: s.width, height: 5))
        }
    }
}
