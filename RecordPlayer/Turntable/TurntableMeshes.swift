import RealityKit

enum TurntableMeshes {
    /// A flat disc facing up, with an image mapped across it: image top toward -z (the top of a top-down view).
    @MainActor
    static func disc(radius: Float, segments: Int = 128) throws -> MeshResource {
        var positions: [SIMD3<Float>] = [.zero]
        var uvs: [SIMD2<Float>] = [[0.5, 0.5]]
        for i in 0..<segments {
            let angle = Float(i) / Float(segments) * 2 * .pi
            let x = cos(angle)
            let z = sin(angle)
            positions.append([x * radius, 0, z * radius])
            uvs.append([0.5 + x / 2, 0.5 - z / 2])
        }

        var indices: [UInt32] = []
        for i in 0..<segments {
            let current = UInt32(1 + i)
            let next = UInt32(1 + (i + 1) % segments)
            indices += [0, next, current]
        }

        var descriptor = MeshDescriptor(name: "disc")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(Array(repeating: [0, 1, 0], count: positions.count))
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }
}
