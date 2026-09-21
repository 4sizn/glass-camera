import Foundation
import MetalKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// One implementation for live preview, full-resolution export and the macOS
/// validation harness. Own each instance from one serial executor.
final class GlassRenderer {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let context: CIContext
    private let buildMap: MTLComputePipelineState
    private let applyGlass: MTLComputePipelineState
    private let linearSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    private var source: MTLTexture?
    private var map: MTLTexture?
    private var lighting: MTLTexture?
    private var mapKey = ""

    init(shaderURL: URL) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw GlassError.message("이 기기에서 Metal 카메라를 사용할 수 없습니다.")
        }
        self.device = device
        self.queue = queue
        context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        let library = try device.makeLibrary(source: String(contentsOf: shaderURL, encoding: .utf8), options: nil)
        guard let mapFunction = library.makeFunction(name: "buildGlassMap"),
              let applyFunction = library.makeFunction(name: "applyGlass") else {
            throw GlassError.message("유리 렌더러를 불러오지 못했습니다.")
        }
        buildMap = try device.makeComputePipelineState(function: mapFunction)
        applyGlass = try device.makeComputePipelineState(function: applyFunction)
    }

    func makeTexture(width: Int, height: Int, format: MTLPixelFormat = .rgba8Unorm,
                     shared: Bool = false, mipmapped: Bool = false) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: mipmapped)
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = shared ? .shared : .private
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw GlassError.message("사진 처리 메모리가 부족합니다.")
        }
        return texture
    }

    static func crop(_ image: CIImage, aspect: CGFloat) -> CIImage {
        let rect = image.extent
        let width = min(rect.width, rect.height*aspect)
        let height = width/aspect
        let region = CGRect(x: rect.midX-width/2, y: rect.midY-height/2, width: width, height: height)
        return image.cropped(to: region).transformed(by: CGAffineTransform(translationX: -region.minX, y: -region.minY))
    }

    func encode(image: CIImage, output: MTLTexture, command: MTLCommandBuffer,
                material: GlassMaterial, tangentHalfFOV: Float, mode: UInt32 = 0) throws {
        let width = output.width, height = output.height
        if source?.width != width || source?.height != height {
            source = try makeTexture(width: width, height: height, format: .rgba16Float, mipmapped: true)
            map = try makeTexture(width: width, height: height, format: .rgba32Float)
            lighting = try makeTexture(width: width, height: height, format: .rgba16Float)
            mapKey = ""
        }
        guard let source, let map, let lighting else { return }
        let cropped = Self.crop(image, aspect: CGFloat(width)/CGFloat(height))
        // CI uses bottom-left coordinates; Metal sample (0,0) is our top-left.
        let resized = cropped.transformed(by: CGAffineTransform(scaleX: CGFloat(width)/cropped.extent.width,
                                                                y: -CGFloat(height)/cropped.extent.height))
            .transformed(by: CGAffineTransform(translationX: 0, y: CGFloat(height)))
        context.render(resized, to: source, commandBuffer: command,
                       bounds: CGRect(x: 0, y: 0, width: width, height: height), colorSpace: linearSpace)
        if mode == 0 {
            guard let blit = command.makeBlitCommandEncoder() else { throw GlassError.message("GPU 처리 실패") }
            blit.generateMipmaps(for: source)
            blit.endEncoding()
        }

        let key = "\(material.hash):\(width):\(height):\(tangentHalfFOV):\(mode == 3)"
        if mapKey != key {
            guard let encoder = command.makeComputeCommandEncoder() else { throw GlassError.message("GPU 처리 실패") }
            var uniforms = material.uniforms(aspect: Float(width)/Float(height), tangentHalfFOV: tangentHalfFOV,
                                             diagnostic: mode == 3 ? 1 : 0)
            encoder.setComputePipelineState(buildMap)
            encoder.setTexture(map, index: 0)
            encoder.setTexture(lighting, index: 1)
            encoder.setBytes(&uniforms, length: MemoryLayout<GlassUniforms>.stride, index: 0)
            dispatch(encoder, width: width, height: height)
            encoder.endEncoding()
            mapKey = key
        }
        guard let encoder = command.makeComputeCommandEncoder() else { throw GlassError.message("GPU 처리 실패") }
        var displayMode = mode
        encoder.setComputePipelineState(applyGlass)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(map, index: 1)
        encoder.setTexture(lighting, index: 2)
        encoder.setTexture(output, index: 3)
        encoder.setBytes(&displayMode, length: MemoryLayout<UInt32>.stride, index: 0)
        dispatch(encoder, width: width, height: height)
        encoder.endEncoding()
    }

    private func dispatch(_ encoder: MTLComputeCommandEncoder, width: Int, height: Int) {
        encoder.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
    }

    func render(image: CIImage, material: GlassMaterial, tangentHalfFOV: Float = 0.7,
                maxDimension: Int? = nil, mode: UInt32 = 0, aspect: CGFloat = 0.75) throws -> CGImage {
        let cropped = Self.crop(image, aspect: aspect)
        let scale = min(1, CGFloat(maxDimension ?? Int(cropped.extent.height))/cropped.extent.height)
        let width = max(1, Int(cropped.extent.width*scale)), height = max(1, Int(cropped.extent.height*scale))
        let output = try makeTexture(width: width, height: height, shared: true)
        guard let command = queue.makeCommandBuffer() else { throw GlassError.message("GPU 처리 실패") }
        try encode(image: cropped, output: output, command: command, material: material,
                   tangentHalfFOV: tangentHalfFOV, mode: mode)
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error { throw error }
        var pixels = [UInt8](repeating: 0, count: width*height*4)
        output.getBytes(&pixels, bytesPerRow: width*4, from: MTLRegionMake2D(0,0,width,height), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: width*4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            throw GlassError.message("사진을 만들지 못했습니다.")
        }
        return cg
    }

    static func write(_ image: CGImage, to url: URL, metadata: [String: Any] = [:]) throws {
        let data = NSMutableData()
        let type = url.pathExtension == "png" ? UTType.png.identifier : UTType.jpeg.identifier
        guard let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil) else {
            throw GlassError.message("사진 파일을 만들지 못했습니다.")
        }
        var properties = metadata
        properties[kCGImageDestinationLossyCompressionQuality as String] = 0.96
        properties[kCGImagePropertyOrientation as String] = 1
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw GlassError.message("사진 인코딩에 실패했습니다.") }
        try (data as Data).write(to: url, options: .atomic)
    }
}
