import Foundation
import CryptoKit
import simd

enum GlassPattern: String, Codable, CaseIterable, Identifiable {
    case quadra, crossLarge, diamond
    var id: String { rawValue }
    var name: String {
        switch self {
        case .quadra: "쿼드라"
        case .crossLarge: "Cross Large"
        case .diamond: "다이아몬드"
        }
    }
    var shaderID: UInt32 {
        switch self { case .quadra: 0; case .crossLarge: 1; case .diamond: 2 }
    }
}

struct GlassControl: Codable, Identifiable {
    let id: String
    let name: String
    let unit: String
    let min: Double
    let max: Double
    let step: Double
}

struct GlassMaterial: Codable {
    let schemaVersion: Int
    let id: String
    let status: String
    let model: String
    let seed: UInt32
    var thickness: Float
    var relief: Float
    var pitch: Float
    var roundness: Float
    var edge: Float
    let ior: Float
    let edgeWidth: Float
    var microHeight: Float
    let glassDistance: Float
    let sceneDistance: Float
    var reflection: Float
    var lightAngle: Float
    let controls: [GlassControl]
    // Omitting the default keeps existing material hashes and saved overrides valid.
    private var patternOverride: GlassPattern?
    var pattern: GlassPattern {
        get { patternOverride ?? .quadra }
        set { patternOverride = newValue == .quadra ? nil : newValue }
    }

    static func load(from url: URL) throws -> Self {
        let result = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try result.validate()
        return result
    }

    func validate() throws {
        guard schemaVersion == 1, status == "prototype", model == "rolled-plate-v3",
              (1.45...1.60).contains(ior), (0.02...0.25).contains(edgeWidth),
              glassDistance > 0.03, sceneDistance > glassDistance + 0.025,
              (0...0.01).contains(microHeight), thickness - relief - microHeight > 0.5 else {
            throw GlassError.message("지원하지 않거나 손상된 유리 재질입니다.")
        }
        let keys = ["thickness", "relief", "pitch", "roundness", "edge", "reflection", "lightAngle"]
        guard controls.count == keys.count, Set(controls.map(\.id)) == Set(keys) else {
            throw GlassError.message("유리 조절 정의가 올바르지 않습니다.")
        }
        for control in controls {
            let value = Double(self[control.id])
            guard value.isFinite, control.min.isFinite, control.max.isFinite,
                  control.step.isFinite, control.step > 0, control.min <= control.max,
                  (control.min...control.max).contains(value) else {
                throw GlassError.message("\(control.name) 값을 확인해 주세요.")
            }
        }
    }

    subscript(_ key: String) -> Float {
        get {
            switch key {
            case "thickness": thickness
            case "relief": relief
            case "pitch": pitch
            case "roundness": roundness
            case "edge": edge
            case "reflection": reflection
            case "lightAngle": lightAngle
            default: .nan
            }
        }
        set {
            switch key {
            case "thickness": thickness = newValue
            case "relief": relief = newValue
            case "pitch": pitch = newValue
            case "roundness": roundness = newValue
            case "edge": edge = newValue
            case "reflection": reflection = newValue
            case "lightAngle": lightAngle = newValue
            default: break
            }
        }
    }

    var canonicalData: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }

    var hash: String { SHA256.hash(data: canonicalData).map { String(format: "%02x", $0) }.joined() }

    func uniforms(aspect: Float, tangentHalfFOV: Float, diagnostic: UInt32 = 0) -> GlassUniforms {
        GlassUniforms(
            optical: SIMD4(thickness / 1000, relief / 1000, pitch / 1000, ior),
            surface: SIMD4(roundness, edge / 1000, edgeWidth, microHeight / 1000),
            scene: SIMD4(glassDistance, sceneDistance, tangentHalfFOV, aspect),
            light: SIMD4(reflection, lightAngle * .pi / 180, 0, 0),
            flags: SIMD4(seed, diagnostic, pattern.shaderID, 0)
        )
    }
}

// Keep aligned with GlassUniforms in Quadra.metal (five 16-byte vectors).
struct GlassUniforms {
    var optical: SIMD4<Float>
    var surface: SIMD4<Float>
    var scene: SIMD4<Float>
    var light: SIMD4<Float>
    var flags: SIMD4<UInt32>
}

enum GlassError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): text }
    }
}
