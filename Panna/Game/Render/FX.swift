import SceneKit

enum FX {
    static let softDot: UIImage = Tex.render(CGSize(width: 64, height: 64), key: "softdot") { c, s in
        let cs = CGColorSpaceCreateDeviceRGB()
        let g = CGGradient(colorsSpace: cs, colors: [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
        c.drawRadialGradient(g, startCenter: CGPoint(x: 32, y: 32), startRadius: 0, endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
    }
    /// Thin bright ring with a soft inner falloff (shockwaves).
    static let ring: UIImage = Tex.render(CGSize(width: 256, height: 256), key: "ring") { c, s in
        let cs = CGColorSpaceCreateDeviceRGB()
        let g = CGGradient(colorsSpace: cs, colors: [UIColor.white.withAlphaComponent(0).cgColor, UIColor.white.withAlphaComponent(0.15).cgColor,
                                                     UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray,
                           locations: [0, 0.78, 0.93, 1])!
        c.drawRadialGradient(g, startCenter: CGPoint(x: 128, y: 128), startRadius: 0, endCenter: CGPoint(x: 128, y: 128), endRadius: 128, options: [])
    }
    static let square: UIImage = Tex.render(CGSize(width: 16, height: 16), key: "sq") { c, s in
        c.setFillColor(UIColor.white.cgColor); c.fill(CGRect(origin: .zero, size: s))
    }
    static let spark: UIImage = Tex.render(CGSize(width: 64, height: 16), key: "spark") { c, s in
        let cs = CGColorSpaceCreateDeviceRGB()
        let g = CGGradient(colorsSpace: cs, colors: [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
        c.drawLinearGradient(g, start: CGPoint(x: 0, y: 8), end: CGPoint(x: 64, y: 8), options: [])
    }

    static func burst(color: UIColor, count: CGFloat, speed: CGFloat, life: CGFloat, size: CGFloat, image: UIImage = softDot, gravity: Bool = false, spread: CGFloat = 180) -> SCNParticleSystem {
        let p = SCNParticleSystem()
        p.birthRate = count
        p.emissionDuration = 0.05
        p.loops = false
        p.particleLifeSpan = life
        p.particleLifeSpanVariation = life * 0.4
        p.particleVelocity = speed
        p.particleVelocityVariation = speed * 0.6
        p.spreadingAngle = spread
        p.particleSize = size
        p.particleSizeVariation = size * 0.5
        p.particleColor = color
        p.particleImage = image
        p.blendMode = .additive
        p.isAffectedByGravity = gravity
        p.acceleration = gravity ? SCNVector3(0, -9, 0) : SCNVector3Zero
        p.dampingFactor = 1.5
        let fade = CAKeyframeAnimation()
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, 0.6, 1]
        p.propertyControllers = [.opacity: SCNParticlePropertyController(animation: fade)]
        return p
    }

    static func confetti(colors: [UIColor]) -> SCNParticleSystem {
        let p = SCNParticleSystem()
        p.birthRate = 500
        p.emissionDuration = 0.1
        p.loops = false
        p.particleLifeSpan = 2.6
        p.particleLifeSpanVariation = 0.8
        p.particleVelocity = 11
        p.particleVelocityVariation = 5
        p.spreadingAngle = 40
        p.emittingDirection = SCNVector3(0, 1, 0)
        p.particleSize = 0.045
        p.particleSizeVariation = 0.02
        p.particleImage = square
        p.particleColor = colors.first ?? .white
        p.particleColorVariation = SCNVector4(0.15, 0.2, 0.2, 0)
        p.isAffectedByGravity = true
        p.acceleration = SCNVector3(0, -6, 0)
        p.dampingFactor = 1.2
        p.particleAngularVelocity = 600
        p.particleAngularVelocityVariation = 400
        p.blendMode = .alpha
        p.isLightingEnabled = false
        return p
    }

    static func aura(color: UIColor) -> SCNParticleSystem {
        let p = SCNParticleSystem()
        p.birthRate = 70
        p.loops = true
        p.particleLifeSpan = 0.7
        p.particleVelocity = 1.4
        p.particleVelocityVariation = 0.6
        p.emittingDirection = SCNVector3(0, 1, 0)
        p.spreadingAngle = 25
        p.particleSize = 0.16
        p.particleSizeVariation = 0.08
        p.particleColor = color
        p.particleImage = softDot
        p.blendMode = .additive
        p.emitterShape = SCNCylinder(radius: 0.35, height: 1.6)
        p.birthLocation = .surface
        let fade = CAKeyframeAnimation()
        fade.values = [0, 1, 0]
        fade.keyTimes = [0, 0.3, 1]
        p.propertyControllers = [.opacity: SCNParticlePropertyController(animation: fade)]
        return p
    }

    static func trail(color: UIColor) -> SCNParticleSystem {
        let p = SCNParticleSystem()
        p.birthRate = 0
        p.loops = true
        p.particleLifeSpan = 0.35
        p.particleVelocity = 0
        p.particleSize = 0.24
        p.particleColor = color
        p.particleImage = softDot
        p.blendMode = .additive
        p.emitterShape = SCNSphere(radius: 0.05)
        let shrink = CAKeyframeAnimation()
        shrink.values = [1, 0.1]
        shrink.keyTimes = [0, 1]
        let fade = CAKeyframeAnimation()
        fade.values = [0.9, 0]
        fade.keyTimes = [0, 1]
        p.propertyControllers = [.size: SCNParticlePropertyController(animation: shrink), .opacity: SCNParticlePropertyController(animation: fade)]
        return p
    }
}
