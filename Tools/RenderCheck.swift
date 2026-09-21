import Foundation
import CoreImage
import ImageIO

@main struct RenderCheck {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let renderer = try GlassRenderer(shaderURL: root.appendingPathComponent("QuadraCamera/Shaders/Quadra.metal"))
        var material = try GlassMaterial.load(from: root.appendingPathComponent("QuadraCamera/Resources/quadra.json"))
        let arguments = CommandLine.arguments
        if let value=arguments.first(where: { $0.hasPrefix("--pattern=") }),
           let pattern=GlassPattern(rawValue: String(value.dropFirst(10))) { material.pattern=pattern }
        for argument in arguments.dropFirst() where argument.contains("=") {
            let pair = argument.split(separator: "=")
            if pair.count == 2, let value = Float(pair[1]) { material[String(pair[0])] = value }
        }
        try material.validate()
        let inputArgument = arguments.first(where: { $0.hasPrefix("--input=") }).map { String($0.dropFirst(8)) }
        let file = inputArgument.map { URL(fileURLWithPath: $0) } ?? root.appendingPathComponent("QuadraCamera/Resources/sample-cat.jpg")
        let prefix = arguments.first(where: { $0.hasPrefix("--prefix=") }).map { String($0.dropFirst(9)) } ?? (inputArgument == nil ? "" : "device-v2-")
        let preserveAspect = arguments.contains("--preserve-aspect")
        guard let input = CIImage(contentsOf: file, options: [.applyOrientationProperty: true]) else {
            throw GlassError.message("Missing sample-cat.jpg")
        }
        for (name, mode) in [("original", UInt32(1)), ("quadra", UInt32(0)), ("diagnostic", UInt32(2))] {
            let start = Date()
            let cg = try renderer.render(image: input, material: material, maxDimension: 1440, mode: mode,
                                         aspect: preserveAspect ? input.extent.width/input.extent.height : 0.75)
            try GlassRenderer.write(cg, to: root.appendingPathComponent("artifacts/\(prefix)\(name).png"))
            print("\(name): \(cg.width)×\(cg.height), \(Int(Date().timeIntervalSince(start)*1000)) ms")
        }
        print("Material \(material.hash)")
    }
}
