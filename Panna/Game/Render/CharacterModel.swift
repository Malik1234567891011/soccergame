import SceneKit
import simd

/// Skinned character data exported from Blender (art/blender/character.py). Loaded once, shared by all instances.
final class CharacterModel {
    struct BoneData: Decodable { let name: String; let parent: Int; let matrix: [Float] }
    struct Group: Decodable { let material: String; let indices: [Int32] }
    struct MeshData: Decodable {
        let name: String
        let slot: String
        let positions: [Float]
        let normals: [Float]
        let uvs: [Float]
        let joints: [Int]
        let weights: [Float]
        let groups: [Group]
    }
    struct File: Decodable {
        let bones: [BoneData]
        let meshes: [MeshData]
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

    static let shared: CharacterModel = {
        guard let url = Bundle.main.url(forResource: "base", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else {
            fatalError("character model missing")
        }
        return CharacterModel(file)
    }()

    init(_ f: File) {
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
            let n = m.positions.count / 3
            let pos = Data(bytes: m.positions, count: m.positions.count * 4)
            let nor = Data(bytes: m.normals, count: m.normals.count * 4)
            let uvd = Data(bytes: m.uvs, count: m.uvs.count * 4)
            let sources = [
                SCNGeometrySource(data: pos, semantic: .vertex, vectorCount: n, usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12),
                SCNGeometrySource(data: nor, semantic: .normal, vectorCount: n, usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12),
                SCNGeometrySource(data: uvd, semantic: .texcoord, vectorCount: n, usesFloatComponents: true, componentsPerVector: 2, bytesPerComponent: 4, dataOffset: 0, dataStride: 8),
            ]
            let jointsU16 = m.joints.map { UInt16($0) }
            let bi = SCNGeometrySource(data: Data(bytes: jointsU16, count: jointsU16.count * 2), semantic: .boneIndices, vectorCount: n,
                                       usesFloatComponents: false, componentsPerVector: 4, bytesPerComponent: 2, dataOffset: 0, dataStride: 8)
            let bw = SCNGeometrySource(data: Data(bytes: m.weights, count: m.weights.count * 4), semantic: .boneWeights, vectorCount: n,
                                       usesFloatComponents: true, componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
            let elements = m.groups.map { SCNGeometryElement(indices: $0.indices, primitiveType: .triangles) }
            let all = m.groups.flatMap { $0.indices }
            return Mesh(name: m.name, slot: m.slot, sources: sources, elements: elements, materialNames: m.groups.map { $0.material },
                        outlineElement: SCNGeometryElement(indices: all, primitiveType: .triangles), boneWeights: bw, boneIndices: bi)
        }
    }

    func boneIndex(_ name: String) -> Int { boneNames.firstIndex(of: name) ?? 0 }

    var hairStyles: [String] { meshes.compactMap { $0.slot.hasPrefix("hair:") ? String($0.slot.dropFirst(5)) : nil } }
}
