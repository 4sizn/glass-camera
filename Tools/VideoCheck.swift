import Foundation
import AVFoundation
import CoreImage

@main struct VideoCheck {
    static func main() async throws {
        let root=URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let shader=root.appendingPathComponent("QuadraCamera/Shaders/Quadra.metal")
        let material=try GlassMaterial.load(from: root.appendingPathComponent("QuadraCamera/Resources/quadra.json"))
        let source=CIImage(contentsOf: root.appendingPathComponent("QuadraCamera/Resources/sample-dog.jpg"))!
        // Use the same input graph and resolution for writer and still paths.
        let image=source.transformed(by: CGAffineTransform(scaleX: 1440/source.extent.height,y: 1440/source.extent.height))
        let recorder=VideoRecorder(shaderURL: shader)
        let file=root.appendingPathComponent("artifacts/video-shader-check.mp4")
        try? FileManager.default.removeItem(at: file)
        try await recorder.start(at: file,audio: false)
        var cross=material; cross.pattern = .crossLarge; cross.pitch=24
        var diamond=material; diamond.pattern = .diamond; diamond.pitch=12
        let variants=[material,cross,diamond]
        for i in 0..<90 {
            recorder.append(image: image,material: variants[i/30],fov: 0.7,time: CMTime(value: Int64(3000+i),timescale: 30))
            try await Task.sleep(for: .milliseconds(40))
        }
        let result=try await recorder.finish()
        let asset=AVURLAsset(url: file)
        let tracks=try await asset.loadTracks(withMediaType: .video)
        let track=tracks.first!
        let size=try await track.load(.naturalSize)
        let duration=try await asset.load(.duration).seconds
        let audio=try await asset.loadTracks(withMediaType: .audio)
        precondition(size.width==1080 && size.height==1440 && audio.isEmpty)
        precondition(duration>2.9 && duration<3.1 && result.frames>=75)
        let reader=try AVAssetReader(asset: asset)
        let output=AVAssetReaderTrackOutput(track: track,outputSettings: [kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
        reader.add(output); precondition(reader.startReading())
        var count=0, previous=CMTime.negativeInfinity
        while let sample=output.copyNextSampleBuffer() {
            let time=CMSampleBufferGetPresentationTimeStamp(sample)
            precondition(time>previous); previous=time; count += 1
        }
        precondition(reader.status == .completed && count==result.frames)
        print("PASS H.264 decode: \(Int(size.width))×\(Int(size.height)), \(duration)s, \(count) frames, increasing timestamps, no audio requested")

        let renderer=try GlassRenderer(shaderURL: shader)
        let generator=AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform=true
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let context=CIContext(), space=CGColorSpace(name: CGColorSpace.sRGB)!
        for (index,settings) in variants.enumerated() {
            let label=settings.pattern.rawValue, time=Double(index)+0.5
            let decoded=try await generator.image(at: CMTime(seconds: time,preferredTimescale: 600)).image
            let expected=try renderer.render(image: image,material: settings,maxDimension: 1440)
            var actualBytes=[UInt8](repeating: 0,count: 1080*1440*4), expectedBytes=actualBytes
            let bounds=CGRect(x: 0,y: 0,width: 1080,height: 1440)
            context.render(CIImage(cgImage: decoded),toBitmap: &actualBytes,rowBytes: 1080*4,bounds: bounds,format: .RGBA8,colorSpace: space)
            context.render(CIImage(cgImage: expected),toBitmap: &expectedBytes,rowBytes: 1080*4,bounds: bounds,format: .RGBA8,colorSpace: space)
            var error=0.0
            for i in stride(from: 0,to: actualBytes.count,by: 4) { for c in 0..<3 {
                error += abs(Double(actualBytes[i+c])-Double(expectedBytes[i+c]))/255
            }}
            error /= Double(1080*1440*3)
            try GlassRenderer.write(decoded,to: root.appendingPathComponent("artifacts/video-check-\(label).png"))
            try GlassRenderer.write(expected,to: root.appendingPathComponent("artifacts/video-expected-\(label).png"))
            FileHandle.standardError.write(Data("\(label) MAE: \(error)\n".utf8))
            precondition(error<0.02,"Video colors/orientation/filter differ from the still renderer")
            print("PASS \(label) live parameter change: video/still RGB MAE=\(error)")
        }

        let empty=root.appendingPathComponent("artifacts/video-empty-check.mp4")
        try await recorder.start(at: empty,audio: false)
        do { _=try await recorder.finish(); preconditionFailure("Empty recording was accepted") }
        catch { precondition(!FileManager.default.fileExists(atPath: empty.path)) }
        print("PASS recorder restart and empty-recording cleanup")
    }
}
