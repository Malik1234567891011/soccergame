import SceneKit
import simd
import UIKit

/// Skinned character data exported from Blender (art/blender/character.py). Loaded once, shared by all instances.
final class CharacterModel {
    struct BoneData: Decodable { let name: String; let parent: Int; let matrix: [Float] }
    struct GroupMeta: Decodable { let material: String; let offset: Int; let count: Int }
    struct MeshMeta: Decodable {
        let name: String
        let slot: String
        let count: Int
        let pos: Int, nor: Int, uv: Int, joints: Int, weights: Int
        let groups: [GroupMeta]
        let index32: Bool?
    }
    struct Header: Decodable {
        let bones: [BoneData]
        let meshes: [MeshMeta]
        let headCenter: [Float]
        let headRadius: Float
    }

    struct Mesh {
        let name: String
        let slot: String
        let sources: [SCNGeometrySource]
        let elements: [SCNGeometryElement]
        let materialNames: [String]
        let outlineElement: SCNGeometryElement
        let boneWeights: SCNGeometrySource
        let boneIndices: SCNGeometrySource
    }

    let boneNames: [String]
    let boneParents: [Int]
    let restWorld: [simd_float4x4]
    let restLocal: [simd_float4x4]
    let meshes: [Mesh]
    let headCenter: SIMD3<Float>
    let headRadius: Float

    static let shared: CharacterModel = CharacterModel.load("base")!
    static var cache: [String: CharacterModel] = [:]
    let texture: UIImage?
    var kitMask: UIImage?
    var kitCal: KitRecolor.Calibration?

    /// Loads a model from the bundle (`name.bin`, optional `name.png` baked texture for unique characters).
    static func load(_ name: String) -> CharacterModel? {
        if let c = cache[name] { return c }
        guard let url = Bundle.main.url(forResource: name, withExtension: "bin"),
              let data = try? Data(contentsOf: url) else { return nil }
        let hlen = Int(data.withUnsafeBytes { $0.load(as: UInt32.self) })
        guard let header = try? JSONDecoder().decode(Header.self, from: data.subdata(in: 4..<(4 + hlen))) else { return nil }
        let blob = data.subdata(in: (4 + hlen)..<data.count)
        let tex = (Bundle.main.url(forResource: name, withExtension: "jpg") ?? Bundle.main.url(forResource: name, withExtension: "png"))
            .flatMap { UIImage(contentsOfFile: $0.path) }
        let m = CharacterModel(header, blob: blob, texture: tex)
        m.kitMask = Bundle.main.url(forResource: name + "_mask", withExtension: "png").flatMap { UIImage(contentsOfFile: $0.path) }
        m.kitCal = Bundle.main.url(forResource: name + "_kit", withExtension: "json").flatMap { try? Data(contentsOf: $0) }.flatMap(KitRecolor.Calibration.load)
        cache[name] = m
        return m
    }

    static func exists(_ name: String) -> Bool { Bundle.main.url(forResource: name, withExtension: "bin") != nil }

    init(_ f: Header, blob: Data, texture: UIImage? = nil) {
        self.texture = texture
        boneNames = f.bones.map { $0.name }
        boneParents = f.bones.map { $0.parent }
        restWorld = f.bones.map { b in
            let m = b.matrix
            return simd_float4x4(columns: (SIMD4(m[0], m[1], m[2], m[3]), SIMD4(m[4], m[5], m[6], m[7]),
                                           SIMD4(m[8], m[9], m[10], m[11]), SIMD4(m[12], m[13], m[14], m[15])))
        }
        var locals: [simd_float4x4] = []
        for (i, w) in restWorld.enumerated() {
            let p = f.bones[i].parent
            locals.append(p >= 0 ? restWorld[p].inverse * w : w)
        }
        restLocal = locals
        headCenter = SIMD3(f.headCenter[0], f.headCenter[1], f.headCenter[2])
        headRadius = f.headRadius
        meshes = f.meshes.map { m in
            let n = m.count
            func slice(_ off: Int, _ bytes: Int) -> Data { blob.subdata(in: off..<(off + bytes)) }
            let sources = [
                SCNGeometrySource(data: slice(m.pos, n * 12), semantic: .vertex, vectorCount: n, usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12),
                SCNGeometrySource(data: slice(m.nor, n * 12), semantic: .normal, vectorCount: n, usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12),
                SCNGeometrySource(data: slice(m.uv, n * 8), semantic: .texcoord, vectorCount: n, usesFloatComponents: true, componentsPerVector: 2, bytesPerComponent: 4, dataOffset: 0, dataStride: 8),
            ]
            let bi = SCNGeometrySource(data: slice(m.joints, n * 8), semantic: .boneIndices, vectorCount: n,
                                       usesFloatComponents: false, componentsPerVector: 4, bytesPerComponent: 2, dataOffset: 0, dataStride: 8)
            let bw = SCNGeometrySource(data: slice(m.weights, n * 16), semantic: .boneWeights, vectorCount: n,
                                       usesFloatComponents: true, componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
            var all = Data()
            let ib = (m.index32 ?? false) ? 4 : 2
            let elements: [SCNGeometryElement] = m.groups.map { g in
                let d = slice(g.offset, g.count * ib)
                all.append(d)
                return SCNGeometryElement(data: d, primitiveType: .triangles, primitiveCount: g.count / 3, bytesPerIndex: ib)
            }
            let total = m.groups.reduce(0) { $0 + $1.count }
            return Mesh(name: m.name, slot: m.slot, sources: sources, elements: elements, materialNames: m.groups.map { $0.material },
                        outlineElement: SCNGeometryElement(data: all, primitiveType: .triangles, primitiveCount: total / 3, bytesPerIndex: ib),
                        boneWeights: bw, boneIndices: bi)
        }
    }

    func boneIndex(_ name: String) -> Int { boneNames.firstIndex(of: name) ?? 0 }

    var hairStyles: [String] { meshes.compactMap { $0.slot.hasPrefix("hair:") ? String($0.slot.dropFirst(5)) : nil } }
}
