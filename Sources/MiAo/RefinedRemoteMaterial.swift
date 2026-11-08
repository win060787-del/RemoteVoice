import AppKit
import SceneKit

enum RefinedRemoteMaterial {
    static func studio() -> NSImage {
        let image = NSImage(size: NSSize(width: 1024, height: 512))
        image.lockFocus()
        let colors: [NSColor] = [0.16, 0.25, 0.68, 0.28, 0.16, 0.56, 0.22].map { NSColor(white: $0, alpha: 1) }
        NSGradient(colors: colors)!.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 512), angle: 0)
        image.unlockFocus()
        return image
    }
    static func brushedRoughness() -> NSImage {
        let image = NSImage(size: NSSize(width: 256, height: 512))
        image.lockFocus()
        for row in 0..<512 {
            let value = 0.37 + Double((row * 37) % 17) / 4000
            NSColor(white: value, alpha: 1).setFill()
            NSRect(x: 0, y: row, width: 256, height: 1).fill()
        }
        image.unlockFocus()
        return image
    }
    /// A revolved solid profile creates a real bevel instead of a flat cylinder edge.
    static func button(radius: Float, height: Float) -> SCNGeometry {
        let segments = 96
        let bevel = min(Float(0.012), height * 0.18)
        let profile: [(Float, Float)] = [
            (radius - bevel, 0), (radius, bevel), (radius, height - bevel), (radius - bevel, height), (0, height),
        ]
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = []
        var indices: [Int32] = []
        for (ring, point) in profile.enumerated() {
            let previous = profile[max(0, ring - 1)], next = profile[min(profile.count - 1, ring + 1)]
            let dr = next.0 - previous.0, dz = next.1 - previous.1
            let length = max(Float(0.00001), sqrt(dr * dr + dz * dz))
            for index in 0..<segments {
                let angle = Float(index) * 2 * .pi / Float(segments)
                vertices.append(SCNVector3(point.0 * cos(angle), point.0 * sin(angle), point.1))
                normals.append(
                    ring == profile.count - 1
                        ? SCNVector3(0, 0, 1)
                        : SCNVector3(dz / length * cos(angle), dz / length * sin(angle), -dr / length))
                if ring > 0 {
                    let a = Int32((ring - 1) * segments + index),
                        b = Int32((ring - 1) * segments + (index + 1) % segments)
                    let c = Int32(ring * segments + index), d = Int32(ring * segments + (index + 1) % segments)
                    indices += [a, b, c, b, d, c]
                }
            }
        }
        return SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }
}
