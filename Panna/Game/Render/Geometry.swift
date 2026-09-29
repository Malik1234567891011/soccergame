import SceneKit

enum Geo {
    /// A spherical cap that can hang lower at the back than at the front — the base of every hairstyle.
    /// Local +z is the face direction. `frontTheta`/`backTheta` are angles from the top pole.
    static func cap(radius: CGFloat, frontTheta: Float, backTheta: Float, sideTheta: Float? = nil, rings: Int = 14, segments: Int = 32) -> SCNGeometry {
        var verts: [SCNVector3] = []
        var norms: [SCNVector3] = []
        var uvs: [CGPoint] = []
        var idx: [Int32] = []
        let side = sideTheta ?? (frontTheta + backTheta) / 2
        for s in 0...segments {
            let phi = Float(s) / Float(segments) * 2 * .pi
            // cos(phi)=1 at front (+z)
            let fz = cos(phi)
            let limit: Float
            if fz >= 0 { limit = side + (frontTheta - side) * fz } else { limit = side + (backTheta - side) * (-fz) }
            for r in 0...rings {
                let theta = Float(r) / Float(rings) * limit
                let st: Float = sin(theta), ct: Float = cos(theta)
                let sp: Float = sin(phi), cp: Float = cos(phi)
                let n = SCNVector3(st * sp, ct, st * cp)
                let rr = Float(radius)
                verts.append(SCNVector3(st * sp * rr, ct * rr, st * cp * rr))
                norms.append(n)
                uvs.append(CGPoint(x: CGFloat(s) / CGFloat(segments), y: CGFloat(r) / CGFloat(rings)))
            }
        }
        let stride = rings + 1
        for s in 0..<segments {
            for r in 0..<rings {
                let a = Int32(s * stride + r), b = Int32((s + 1) * stride + r)
                idx += [a, b, a + 1, a + 1, b, b + 1]
            }
        }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: norms), SCNGeometrySource(textureCoordinates: uvs)],
                            elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        return g
    }

    /// A flat disc/ring lying on the ground plane.
    static func ring(inner: CGFloat, outer: CGFloat, segments: Int = 48) -> SCNGeometry {
        var verts: [SCNVector3] = []
        var norms: [SCNVector3] = []
        var uvs: [CGPoint] = []
        var idx: [Int32] = []
        for s in 0...segments {
            let a: Float = Float(s) / Float(segments) * 2 * .pi
            let ca: Float = cos(a), sa: Float = sin(a)
            let ri = Float(inner), ro = Float(outer)
            verts.append(SCNVector3(ca * ri, 0, sa * ri))
            verts.append(SCNVector3(ca * ro, 0, sa * ro))
            norms += [SCNVector3(0, 1, 0), SCNVector3(0, 1, 0)]
            uvs += [CGPoint(x: CGFloat(s) / CGFloat(segments), y: 0), CGPoint(x: CGFloat(s) / CGFloat(segments), y: 1)]
        }
        for s in 0..<segments {
            let a = Int32(s * 2)
            idx += [a, a + 2, a + 1, a + 1, a + 2, a + 3]
        }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: norms), SCNGeometrySource(textureCoordinates: uvs)],
                           elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
    }

    static func node(_ g: SCNGeometry, _ m: SCNMaterial, at p: SCNVector3 = SCNVector3Zero) -> SCNNode {
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.position = p
        return n
    }
}

extension SCNVector3 {
    static func + (a: SCNVector3, b: SCNVector3) -> SCNVector3 { SCNVector3(a.x + b.x, a.y + b.y, a.z + b.z) }
    static func - (a: SCNVector3, b: SCNVector3) -> SCNVector3 { SCNVector3(a.x - b.x, a.y - b.y, a.z - b.z) }
    static func * (a: SCNVector3, s: Float) -> SCNVector3 { SCNVector3(a.x * s, a.y * s, a.z * s) }
    var len: Float { (x * x + y * y + z * z).squareRoot() }
}
