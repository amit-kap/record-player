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

    /// A flat ring facing up, mapped like `disc`, whose surface direction points out from the centre, across a
    /// record's grooves. A grooved material stretches its highlights along that direction.
    @MainActor
    /// - Parameter rise: how much higher the inner edge sits than the outer one, for a sloped ring.
    static func ring(inner: Float, outer: Float, rise: Float = 0, segments: Int = 256) throws -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var tangents: [SIMD3<Float>] = []
        var bitangents: [SIMD3<Float>] = []
        for i in 0..<segments {
            let angle = Float(i) / Float(segments) * 2 * .pi
            let x = cos(angle)
            let z = sin(angle)
            for radius in [inner, outer] {
                positions.append([x * radius, radius == inner ? rise : 0, z * radius])
                uvs.append([0.5 + x * radius / outer / 2, 0.5 - z * radius / outer / 2])
                tangents.append([x, 0, z])
                bitangents.append([-z, 0, x])
            }
        }

        var indices: [UInt32] = []
        for i in 0..<segments {
            let a = UInt32(i * 2)
            let b = UInt32((i + 1) % segments * 2)
            indices += [a, b, a + 1, a + 1, b, b + 1]
        }

        var descriptor = MeshDescriptor(name: "ring")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(Array(repeating: [0, 1, 0], count: positions.count))
        descriptor.tangents = MeshBuffers.Tangents(tangents)
        descriptor.bitangents = MeshBuffers.Tangents(bitangents)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }

    /// A ring of small round dots facing up, `count` of them at `radius` from the centre. `slope` tilts each dot
    /// down toward the outside, to lie on a sloped rim.
    @MainActor
    static func dotRing(
        radius: Float, count: Int, dotRadius: Float, slope: Float, segments: Int = 12
    ) throws -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for dot in 0..<count {
            let angle = Float(dot) / Float(count) * 2 * .pi
            let centre = SIMD2<Float>(cos(angle), sin(angle)) * radius
            let first = UInt32(positions.count)
            positions.append([centre.x, 0, centre.y])
            for i in 0..<segments {
                let around = Float(i) / Float(segments) * 2 * .pi
                let point = centre + SIMD2<Float>(cos(around), sin(around)) * dotRadius
                positions.append([point.x, (radius - simd_length(point)) * slope, point.y])
            }
            for i in 0..<segments {
                indices += [first, first + 1 + UInt32((i + 1) % segments), first + 1 + UInt32(i)]
            }
        }

        var descriptor = MeshDescriptor(name: "dotRing")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(Array(repeating: [0, 1, 0], count: positions.count))
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }
}
