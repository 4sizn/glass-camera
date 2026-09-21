import Foundation
import AVFoundation
import CoreImage
import Metal

struct VideoRecordingResult {
    let url: URL
    let duration: Double
    let frames: Int
    let audioBuffers: Int
}

/// Writer and GPU resources belong to one serial queue. Capture callbacks never
/// wait for the encoder: at most two video and 32 audio buffers can be pending.
final class VideoRecorder: @unchecked Sendable {
    private let queue = DispatchQueue(label: "quadra.recording",qos: .userInitiated)
    private let lock = NSLock()
    private let videoSlots = DispatchSemaphore(value: 2)
    private let audioSlots = DispatchSemaphore(value: 32)
    private var accepting = false
    private let shaderURL: URL
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var renderer: GlassRenderer?
    private var textureCache: CVMetalTextureCache?
    private var destination: URL?
    private var firstTime: CMTime?
    private var lastTime: CMTime?
    private var failure: Error?
    private var frameCount = 0
    private var audioCount = 0
    var onFailure: ((Error) -> Void)?

    init(shaderURL: URL) { self.shaderURL=shaderURL }

    func start(at url: URL, audio: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void,Error>) in
            queue.async {
                guard self.writer == nil else {
                    continuation.resume(throwing: GlassError.message("이전 영상을 저장 중입니다.")); return
                }
                do {
                    let temporary=url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent)")
                    let writer=try AVAssetWriter(outputURL: temporary,fileType: .mp4)
                    self.writer=writer; self.destination=url
                    let video=AVAssetWriterInput(mediaType: .video,outputSettings: [
                        AVVideoCodecKey: AVVideoCodecType.h264,
                        AVVideoWidthKey: 1080, AVVideoHeightKey: 1440,
                        AVVideoColorPropertiesKey: [
                            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                            AVVideoTransferFunctionKey: kCVImageBufferTransferFunction_sRGB as String,
                            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
                        ],
                        AVVideoCompressionPropertiesKey: [
                            AVVideoAverageBitRateKey: 10_000_000,
                            AVVideoExpectedSourceFrameRateKey: 30,
                            AVVideoMaxKeyFrameIntervalKey: 30,
                            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                        ]
                    ])
                    video.expectsMediaDataInRealTime=true
                    guard writer.canAdd(video) else { throw GlassError.message("동영상 인코더를 준비하지 못했습니다.") }
                    writer.add(video); self.videoInput=video
                    self.adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video,sourcePixelBufferAttributes: [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                        kCVPixelBufferWidthKey as String: 1080, kCVPixelBufferHeightKey as String: 1440,
                        kCVPixelBufferMetalCompatibilityKey as String: true,
                        kCVPixelBufferIOSurfacePropertiesKey as String: [:]
                    ])
                    if audio {
                        let input=AVAssetWriterInput(mediaType: .audio,outputSettings: [
                            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
                            AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128_000
                        ])
                        input.expectsMediaDataInRealTime=true
                        guard writer.canAdd(input) else { throw GlassError.message("오디오 인코더를 준비하지 못했습니다.") }
                        writer.add(input); self.audioInput=input
                    }
                    let renderer=try GlassRenderer(shaderURL: self.shaderURL)
                    self.renderer=renderer
                    guard CVMetalTextureCacheCreate(nil,nil,renderer.device,nil,&self.textureCache)==kCVReturnSuccess,
                          writer.startWriting() else { throw writer.error ?? GlassError.message("녹화를 시작하지 못했습니다.") }
                    self.firstTime=nil; self.lastTime=nil; self.failure=nil
                    self.frameCount=0; self.audioCount=0
                    self.lock.lock(); self.accepting=true; self.lock.unlock()
                    continuation.resume()
                } catch {
                    self.discard()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func append(image: CIImage, material: GlassMaterial, fov: Float, time: CMTime) {
        lock.lock(); defer { lock.unlock() }
        guard accepting, videoSlots.wait(timeout: .now()) == .success else { return }
        queue.async {
            defer { self.videoSlots.signal() }
            autoreleasepool {
                do { try self.write(image: image,material: material,fov: fov,time: time) }
                catch { self.fail(error) }
            }
        }
    }

    private func write(image: CIImage, material: GlassMaterial, fov: Float, time: CMTime) throws {
        guard failure == nil, let writer, let videoInput, let adaptor, let renderer, let textureCache,
              time.isNumeric else { return }
        guard writer.status == .writing else { throw writer.error ?? GlassError.message("녹화가 중단되었습니다.") }
        if let lastTime, CMTimeGetSeconds(time-lastTime)<1.0/30.0-0.001 { return }
        guard videoInput.isReadyForMoreMediaData else { return }
        if firstTime == nil { writer.startSession(atSourceTime: time); firstTime=time }
        guard let pool=adaptor.pixelBufferPool else { throw GlassError.message("동영상 버퍼를 만들지 못했습니다.") }
        var pixelBuffer: CVPixelBuffer?
        let allocation=CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil,pool,
            [kCVPixelBufferPoolAllocationThresholdKey as String: 6] as CFDictionary,&pixelBuffer)
        if allocation == kCVReturnWouldExceedAllocationThreshold { return }
        guard allocation == kCVReturnSuccess, let pixelBuffer else { throw GlassError.message("동영상 메모리가 부족합니다.") }
        // The shared shader writes sRGB-encoded RGB, not Rec.709 transfer values.
        CVBufferSetAttachment(pixelBuffer,kCVImageBufferColorPrimariesKey,kCVImageBufferColorPrimaries_ITU_R_709_2,.shouldPropagate)
        CVBufferSetAttachment(pixelBuffer,kCVImageBufferTransferFunctionKey,kCVImageBufferTransferFunction_sRGB,.shouldPropagate)
        CVBufferSetAttachment(pixelBuffer,kCVImageBufferCGColorSpaceKey,CGColorSpace(name: CGColorSpace.sRGB)!, .shouldPropagate)
        var metalBuffer: CVMetalTexture?
        let usage=[kCVMetalTextureUsage as String: MTLTextureUsage.shaderWrite.rawValue] as CFDictionary
        guard CVMetalTextureCacheCreateTextureFromImage(nil,textureCache,pixelBuffer,usage,.bgra8Unorm,1080,1440,0,&metalBuffer)==kCVReturnSuccess,
              let metalBuffer, let output=CVMetalTextureGetTexture(metalBuffer),
              let command=renderer.queue.makeCommandBuffer() else { throw GlassError.message("동영상 GPU 버퍼 오류") }
        try renderer.encode(image: image,output: output,command: command,material: material,tangentHalfFOV: fov)
        command.commit(); command.waitUntilCompleted()
        if let error=command.error { throw error }
        guard adaptor.append(pixelBuffer,withPresentationTime: time) else { throw writer.error ?? GlassError.message("영상 프레임을 저장하지 못했습니다.") }
        lastTime=time; frameCount += 1
    }

    func appendAudio(_ sample: CMSampleBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard accepting, audioSlots.wait(timeout: .now()) == .success else { return }
        queue.async {
            defer { self.audioSlots.signal() }
            guard self.failure == nil, let input=self.audioInput, let first=self.firstTime,
                  CMSampleBufferDataIsReady(sample), CMSampleBufferGetPresentationTimeStamp(sample)>=first,
                  input.isReadyForMoreMediaData else { return }
            if input.append(sample) { self.audioCount += 1 }
            else { self.fail(self.writer?.error ?? GlassError.message("녹음이 중단되었습니다.")) }
        }
    }

    func finish() async throws -> VideoRecordingResult {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock(); accepting=false
            queue.async {
                guard let writer=self.writer, let destination=self.destination,
                      let first=self.firstTime, let last=self.lastTime, self.frameCount>0, self.failure == nil else {
                    let error=self.failure ?? GlassError.message("녹화된 장면이 없습니다. 잠시 녹화한 뒤 종료해 주세요.")
                    self.discard(); continuation.resume(throwing: error); return
                }
                let end=last+CMTime(value: 1,timescale: 30)
                writer.endSession(atSourceTime: end)
                self.videoInput?.markAsFinished(); self.audioInput?.markAsFinished()
                writer.finishWriting {
                    self.queue.async {
                        do {
                            guard writer.status == .completed else { throw writer.error ?? GlassError.message("동영상 파일을 완성하지 못했습니다.") }
                            try FileManager.default.moveItem(at: writer.outputURL,to: destination)
                            let result=VideoRecordingResult(url: destination,duration: CMTimeGetSeconds(end-first),frames: self.frameCount,audioBuffers: self.audioCount)
                            self.clear(); continuation.resume(returning: result)
                        } catch { self.discard(); continuation.resume(throwing: error) }
                    }
                }
            }
            lock.unlock()
        }
    }

    private func fail(_ error: Error) {
        guard failure == nil else { return }
        failure=error
        lock.lock(); accepting=false; lock.unlock()
        onFailure?(error)
    }

    private func discard() {
        lock.lock(); accepting=false; lock.unlock()
        if let writer {
            if writer.status == .writing || writer.status == .unknown { writer.cancelWriting() }
            try? FileManager.default.removeItem(at: writer.outputURL)
        }
        clear()
    }

    private func clear() {
        writer=nil; videoInput=nil; audioInput=nil; adaptor=nil
        renderer=nil; textureCache=nil; destination=nil
        firstTime=nil; lastTime=nil; failure=nil
    }
}
