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

    static func material(_ color: UIColor, texture: UIImage? = nil, spec: Float = 0.15, rim: Float? = nil, emission: UIColor? = nil) -> SCNMaterial {
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
        m.setValue(NSValue(scnVector3: SCNVector3(st.shadowTint.x, st.shadowTint.y, st.shadowTint.z)), forKey: "shadowTint")
        m.setValue(NSValue(scnVector3: SCNVector3(st.rimColor.x, st.rimColor.y, st.rimColor.z)), forKey: "rimColor")
        m.setValue(NSNumber(value: rim ?? st.rimAmount), forKey: "rimAmount")
        m.setValue(NSNumber(value: spec), forKey: "specAmount")
        return m
    }

    static func outlineMaterial(width: Float = 0.016) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = style.outline
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
