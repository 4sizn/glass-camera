import Foundation
import AVFoundation
import CoreImage

@main struct InspectVideo {
    static func main() async throws {
        for path in CommandLine.arguments.dropFirst() {
            let url=URL(fileURLWithPath: path), asset=AVURLAsset(url: URL(fileURLWithPath: path))
            let duration=try await asset.load(.duration).seconds
            let video=try await asset.loadTracks(withMediaType: .video).first!
            let size=try await video.load(.naturalSize)
            let videoRange=try await video.load(.timeRange)
            let reader=try AVAssetReader(asset: asset)
            let output=AVAssetReaderTrackOutput(track: video,outputSettings: [kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
            output.alwaysCopiesSampleData=false
            reader.add(output); precondition(reader.startReading())
            var count=0, previous=CMTime.negativeInfinity
            while let sample=output.copyNextSampleBuffer() {
                let time=CMSampleBufferGetPresentationTimeStamp(sample)
                precondition(time>previous && CMSampleBufferGetImageBuffer(sample) != nil)
                previous=time; count += 1
            }
            precondition(reader.status == .completed && count>0)
            var record: [String:Any] = ["file":url.lastPathComponent,"width":Int(size.width),"height":Int(size.height),
                "duration":duration,"decodedFrames":count,"averageFPS":Double(count)/videoRange.duration.seconds,
                "videoStart":videoRange.start.seconds,"videoEnd":videoRange.end.seconds]
            if let audio=try await asset.loadTracks(withMediaType: .audio).first {
                let range=try await audio.load(.timeRange)
                let audioReader=try AVAssetReader(asset: asset)
                let pcm=AVAssetReaderTrackOutput(track: audio,outputSettings: [AVFormatIDKey:kAudioFormatLinearPCM,
                    AVLinearPCMIsFloatKey:true,AVLinearPCMBitDepthKey:32,AVLinearPCMIsNonInterleaved:false])
                audioReader.add(pcm); precondition(audioReader.startReading())
                var samples=0, squareSum=0.0, peak: Float=0
                while let sample=pcm.copyNextSampleBuffer(), let buffer=CMSampleBufferGetDataBuffer(sample) {
                    var values=[Float](repeating: 0,count: CMBlockBufferGetDataLength(buffer)/4)
                    let status=values.withUnsafeMutableBytes { bytes in
                        CMBlockBufferCopyDataBytes(buffer,atOffset: 0,dataLength: bytes.count,destination: bytes.baseAddress!)
                    }
                    precondition(status==noErr)
                    for value in values { precondition(value.isFinite); squareSum += Double(value*value); peak=max(peak,abs(value)) }
                    samples += values.count
                }
                precondition(audioReader.status == .completed && samples>0)
                record["audioSamples"]=samples; record["audioRMS"]=sqrt(squareSum/Double(samples)); record["audioPeak"]=peak
                record["audioStart"]=range.start.seconds; record["audioEnd"]=range.end.seconds
                precondition(abs(range.start.seconds-videoRange.start.seconds)<0.3 && abs(range.end.seconds-videoRange.end.seconds)<0.3)
            } else { record["audioSamples"]=0 }
            let generator=AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform=true
            let frame=try await generator.image(at: CMTime(seconds: min(1,duration/2),preferredTimescale: 600)).image
            try GlassRenderer.write(frame,to: url.deletingPathExtension().appendingPathExtension("png"))
            let json=try JSONSerialization.data(withJSONObject: record,options: [.sortedKeys])
            print(String(data: json,encoding: .utf8)!)
        }
    }
}
