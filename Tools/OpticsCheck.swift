import Foundation
import Metal
import simd
import CoreImage

@main struct OpticsCheck {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let shader = root.appendingPathComponent("QuadraCamera/Shaders/Quadra.metal")
        let material = try GlassMaterial.load(from: root.appendingPathComponent("QuadraCamera/Resources/quadra.json"))
        let renderer = try GlassRenderer(shaderURL: shader)
        let device = renderer.device
        let library = try device.makeLibrary(source: String(contentsOf: shader, encoding: .utf8), options: nil)
        let surfacePipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "probeSurface")!)
        let mapPipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "buildGlassMap")!)
        let uniforms = material.uniforms(aspect: 0.75, tangentHalfFOV: 0.7)
        let pitch = material.pitch/1000
        var points = [SIMD2<Float>]()
        let epsilon = pitch*0.0001
        for i in 0..<1000 {
            let x = Float(i%41)/40*8-4, y = Float(i/41)/24*6-3
            let p = SIMD2(x,y)*pitch
            points += [p,p+SIMD2(epsilon,0),p-SIMD2(epsilon,0),p+SIMD2(0,epsilon),p-SIMD2(0,epsilon)]
        }
        for i in -10...10 {
            let p = SIMD2((Float(i)-0.19)*pitch,Float(i)*pitch*0.231)
            points += [p,p+SIMD2(epsilon,0),p-SIMD2(epsilon,0),p+SIMD2(0,epsilon),p-SIMD2(0,epsilon)]
        }
        func surfaces(_ points: [SIMD2<Float>], using probeUniforms: GlassUniforms? = nil) -> [SIMD4<Float>] {
            let input = device.makeBuffer(bytes: points,length: points.count*MemoryLayout<SIMD2<Float>>.stride)!
            let output = device.makeBuffer(length: points.count*MemoryLayout<SIMD4<Float>>.stride)!
            let command = renderer.queue.makeCommandBuffer()!
            let encoder = command.makeComputeCommandEncoder()!
            var u = probeUniforms ?? uniforms
            encoder.setComputePipelineState(surfacePipeline)
            encoder.setBuffer(input,offset: 0,index: 0)
            encoder.setBuffer(output,offset: 0,index: 1)
            encoder.setBytes(&u,length: MemoryLayout<GlassUniforms>.stride,index: 2)
            encoder.dispatchThreads(MTLSize(width: points.count,height: 1,depth: 1),threadsPerThreadgroup: MTLSize(width: 64,height: 1,depth: 1))
            encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
            precondition(command.error == nil)
            return Array(UnsafeBufferPointer(start: output.contents().assumingMemoryBound(to: SIMD4<Float>.self),count: points.count))
        }
        let samples = surfaces(points)
        precondition(samples == surfaces(points), "Fixed seed is not deterministic")
        var normalErrors = [Float]()
        for i in stride(from: 0,to: samples.count,by: 5) {
            let s = samples[i]
            let finite = SIMD2((samples[i+1].x-samples[i+2].x)/(2*epsilon), (samples[i+3].x-samples[i+4].x)/(2*epsilon))
            let n1 = simd_normalize(SIMD3(-s.y,-s.z,1)), n2 = simd_normalize(SIMD3(-finite.x,-finite.y,1))
            normalErrors.append(acos(min(1,max(-1,simd_dot(n1,n2))))*180 / .pi)
            precondition(s.x.isFinite && s.y.isFinite && s.z.isFinite && material.thickness/1000+s.x > 0.0005)
        }
        normalErrors.sort()
        precondition(normalErrors[Int(Float(normalErrors.count)*0.95)] < 0.5 && normalErrors.last! < 2)
        print("PASS analytic normals vs finite difference: p95=\(normalErrors[Int(Float(normalErrors.count)*0.95)])°, max=\(normalErrors.last!)°")

        // At grid crossings the crown and edge derivatives vanish. The join
        // must retain the mean neighboring facet slope, not reset to zero.
        var seamUniforms=uniforms
        seamUniforms.surface.w=0
        var maxSeamError: Float=0, nonflatJoins=0
        for axis in 0...1 { for i in -8...8 {
            let p=(SIMD2(Float(i),Float(i+2))-SIMD2(0.19,0.37))*pitch
            var offset=SIMD2<Float>.zero
            offset[axis]=pitch*0.3
            let values=surfaces([p-offset,p,p+offset],using: seamUniforms)
            let expected=(values[0][axis+1]+values[2][axis+1])*0.5
            maxSeamError=max(maxSeamError,abs(values[1][axis+1]-expected))
            if abs(values[1][axis+1])>0.005 { nonflatJoins += 1 }
        }}
        precondition(maxSeamError<0.0001 && nonflatJoins>20, "Artificial flat seams returned")
        print("PASS shared facet slope at joins: max gradient error=\(maxSeamError), \(nonflatJoins)/34 nonflat")

        func map(width: Int,height: Int,uniforms: GlassUniforms) throws -> [SIMD4<Float>] {
            let map = try renderer.makeTexture(width: width,height: height,format: .rgba32Float,shared: true)
            let light = try renderer.makeTexture(width: width,height: height,format: .rgba16Float)
            let command = renderer.queue.makeCommandBuffer()!, encoder = command.makeComputeCommandEncoder()!
            var u = uniforms
            encoder.setComputePipelineState(mapPipeline)
            encoder.setTexture(map,index: 0); encoder.setTexture(light,index: 1)
            encoder.setBytes(&u,length: MemoryLayout<GlassUniforms>.stride,index: 0)
            encoder.dispatchThreads(MTLSize(width: width,height: height,depth: 1),threadsPerThreadgroup: MTLSize(width: 16,height: 16,depth: 1))
            encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
            if let error=command.error { throw error }
            var values=[SIMD4<Float>](repeating: .zero,count: width*height)
            map.getBytes(&values,bytesPerRow: width*16,from: MTLRegionMake2D(0,0,width,height),mipmapLevel: 0)
            return values
        }
        var flat = uniforms
        flat.optical.y=0; flat.surface.y=0; flat.surface.w=0
        let flatMap = try map(width: 300,height: 400,uniforms: flat)
        var maxPlateError: Float=0
        for y in 0..<400 { for x in 0..<300 {
            let uv=(SIMD2(Float(x),Float(y))+0.5)/SIMD2(300,400)
            let proj=SIMD2<Float>(1.05,1.4)
            let ray=simd_normalize(SIMD3((uv.x-0.5)*proj.x,(uv.y-0.5)*proj.y,1))
            let eta=Float(1.0003)/material.ior
            let inside=SIMD3(ray.x*eta,ray.y*eta,sqrt(1-eta*eta*(ray.x*ray.x+ray.y*ray.y)))
            let p1=ray*(material.glassDistance/ray.z)
            let p2=p1+inside*(material.thickness/1000/inside.z)
            let q=p2+ray*((material.sceneDistance-p2.z)/ray.z)
            let expected=SIMD2(q.x,q.y)/(material.sceneDistance*proj)+0.5
            let actual=flatMap[y*300+x]
            maxPlateError=max(maxPlateError,simd_length((SIMD2(actual.x,actual.y)-expected)*SIMD2(300,400)))
        }}
        precondition(maxPlateError < 0.01, "Parallel plate refraction mismatch")
        print("PASS double refraction / parallel plate analytic reference: max=\(maxPlateError) px")
        flat.optical.w=1.0003
        let identity=try map(width: 300,height: 400,uniforms: flat)
        for y in 0..<400 { for x in 0..<300 {
            let uv=(SIMD2(Float(x),Float(y))+0.5)/SIMD2(300,400)
            let actual=identity[y*300+x]
            precondition(simd_length(SIMD2(actual.x,actual.y)-uv)<0.000001)
        }}
        print("PASS no-index-contrast identity")
        let small=try map(width: 300,height: 400,uniforms: uniforms)
        let large=try map(width: 900,height: 1200,uniforms: uniforms)
        var maxResolutionError: Float=0
        for y in 0..<400 { for x in 0..<300 {
            let a=small[y*300+x], b=large[(y*3+1)*900+x*3+1]
            maxResolutionError=max(maxResolutionError,simd_length(SIMD2(a.x-b.x,a.y-b.y))*1200)
            precondition(a.x.isFinite && a.y.isFinite && a.w==0)
        }}
        precondition(maxResolutionError < 0.1)
        print("PASS preview/capture normalized map parity: max=\(maxResolutionError) px at 1200 high")
        let edges=small.filter { $0.z>0 }.count
        print("Default map: \(100*Float(edges)/Float(small.count))% source outside; 0 invalid/TIR")

        // Extreme supported control combinations must remain finite, including TIR.
        for relief: Float in [0,3] { for pitch: Float in [10,40] { for edge: Float in [0,0.5] {
            var candidate=material; candidate.relief=relief; candidate.pitch=pitch; candidate.edge=edge
            try candidate.validate()
            let values=try map(width: 90,height: 120,uniforms: candidate.uniforms(aspect: 0.75,tangentHalfFOV: 0.7))
            precondition(values.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.x>=0 && $0.x<=1 && $0.y>=0 && $0.y<=1 })
        }}}
        print("PASS 8 control extremes: finite bounded output")
        let restored=try JSONDecoder().decode(GlassMaterial.self,from: material.canonicalData)
        precondition(restored.hash==material.hash)
        var edited=material; edited.relief=0.5
        precondition(edited.hash != material.hash)
        edited.relief=material.relief
        precondition(edited.hash==material.hash)
        print("PASS material round-trip/hash/reset")

        precondition(material.hash == "407fb1384a4e65705f27572184871688d073edb1d7f0034e76dcb5dc473ed6d2",
                     "Adding patterns changed the legacy default hash")
        for pattern in GlassPattern.allCases where pattern != .quadra {
            var patterned=material; patterned.pattern=pattern
            let decoded=try JSONDecoder().decode(GlassMaterial.self,from: patterned.canonicalData)
            precondition(decoded.pattern==pattern && decoded.hash==patterned.hash && patterned.hash != material.hash)
            var u=patterned.uniforms(aspect: 0.75,tangentHalfFOV: 0.7)
            let values=surfaces(points,using: u)
            var errors=[Float]()
            for i in stride(from: 0,to: values.count,by: 5) {
                let s=values[i]
                let finite=SIMD2((values[i+1].x-values[i+2].x)/(2*epsilon),(values[i+3].x-values[i+4].x)/(2*epsilon))
                let a=simd_normalize(SIMD3(-s.y,-s.z,1)), b=simd_normalize(SIMD3(-finite.x,-finite.y,1))
                errors.append(acos(min(1,max(-1,simd_dot(a,b))))*180 / .pi)
                precondition(s.x.isFinite && s.y.isFinite && s.z.isFinite && material.thickness/1000+s.x>0.0005)
            }
            errors.sort()
            precondition(errors[Int(Double(errors.count)*0.95)]<0.5 && errors.last!<2)
            let patternMap=try map(width: 300,height: 400,uniforms: u)
            let patternLarge=try map(width: 900,height: 1200,uniforms: u)
            var difference: Float=0, parity: Float=0
            for y in 0..<400 { for x in 0..<300 {
                let a=patternMap[y*300+x], b=patternLarge[(y*3+1)*900+x*3+1]
                precondition(a.x.isFinite && a.y.isFinite && a.w==0)
                difference += simd_length(SIMD2(a.x-small[y*300+x].x,a.y-small[y*300+x].y))
                parity=max(parity,simd_length(SIMD2(a.x-b.x,a.y-b.y))*1200)
            }}
            precondition(difference/Float(patternMap.count)>0.001 && parity<0.1)
            u.surface.w=0
            if pattern == .crossLarge {
                let p=SIMD2<Float>(0.0143,-0.0101)
                let a=surfaces([p,p+SIMD2(2*pitch,0),p+SIMD2(0,2*pitch)],using: u)
                precondition(simd_length(a[0]-a[1])<0.0001 && simd_length(a[0]-a[2])<0.0001)
            } else {
                let p=SIMD2<Float>(0.0143,-0.0101), c: Float=sqrt(0.5)
                let rotated=SIMD2(p.x+p.y,p.y-p.x)*c
                let actual=surfaces([p],using: u)[0]
                u.flags.z=0
                let original=surfaces([rotated],using: u)[0]
                let expected=SIMD2(original.y-original.z,original.y+original.z)*c
                precondition(abs(actual.x-original.x)<0.000001 && simd_length(SIMD2(actual.y,actual.z)-expected)<0.00001)
            }
            for relief: Float in [0,3] { for pitch: Float in [10,40] { for roundness: Float in [2,8] {
                var extreme=patterned; extreme.relief=relief; extreme.pitch=pitch; extreme.roundness=roundness
                let output=try map(width: 90,height: 120,uniforms: extreme.uniforms(aspect: 0.75,tangentHalfFOV: 0.7))
                precondition(output.allSatisfy { $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) })
            }}}
            print("PASS \(pattern.rawValue): hash, normals max=\(errors.last!)°, map parity=\(parity) px, distinct refraction, geometry and 8 extremes")
            patterned.pattern = .quadra
            precondition(patterned.hash==material.hash)
        }

        // A compressed two-pixel checker must converge to its linear-light
        // average. Sparse taps alias it; mip filtering must also preserve 1:1.
        let filterPipeline=try device.makeComputePipelineState(function: library.makeFunction(name: "applyGlass")!)
        let checker=try renderer.makeTexture(width: 256,height: 256,shared: true,mipmapped: true)
        var checkerBytes=[UInt8](repeating: 255,count: 256*256*4)
        for y in 0..<256 { for x in 0..<256 {
            let v=UInt8(((x/2+y/2)%2)*255)
            for c in 0..<3 { checkerBytes[(y*256+x)*4+c]=v }
        }}
        checker.replace(region: MTLRegionMake2D(0,0,256,256),mipmapLevel: 0,withBytes: checkerBytes,bytesPerRow: 256*4)
        for dimension in [16,256] {
            let warp=try renderer.makeTexture(width: dimension,height: dimension,format: .rgba32Float,shared: true)
            let light=try renderer.makeTexture(width: dimension,height: dimension,format: .rgba32Float,shared: true)
            let output=try renderer.makeTexture(width: dimension,height: dimension,shared: true)
            var uv=[SIMD4<Float>](), lights=[SIMD4<Float>](repeating: SIMD4(0,0,0,1),count: dimension*dimension)
            for y in 0..<dimension { for x in 0..<dimension {
                let phase: Float=dimension==16 ? 0.5/256 : 0
                uv.append(SIMD4((Float(x)+0.5)/Float(dimension)+phase,(Float(y)+0.5)/Float(dimension)+phase,0,0))
            }}
            warp.replace(region: MTLRegionMake2D(0,0,dimension,dimension),mipmapLevel: 0,withBytes: &uv,bytesPerRow: dimension*16)
            light.replace(region: MTLRegionMake2D(0,0,dimension,dimension),mipmapLevel: 0,withBytes: &lights,bytesPerRow: dimension*16)
            let command=renderer.queue.makeCommandBuffer()!, blit=command.makeBlitCommandEncoder()!
            blit.generateMipmaps(for: checker); blit.endEncoding()
            let encoder=command.makeComputeCommandEncoder()!
            var mode: UInt32=0
            encoder.setComputePipelineState(filterPipeline)
            for (index,texture) in [checker,warp,light,output].enumerated() { encoder.setTexture(texture,index: index) }
            encoder.setBytes(&mode,length: 4,index: 0)
            encoder.dispatchThreads(MTLSize(width: dimension,height: dimension,depth: 1),threadsPerThreadgroup: MTLSize(width: 16,height: 16,depth: 1))
            encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
            precondition(command.error==nil)
            var pixels=[UInt8](repeating: 0,count: dimension*dimension*4), maxError=0
            output.getBytes(&pixels,bytesPerRow: dimension*4,from: MTLRegionMake2D(0,0,dimension,dimension),mipmapLevel: 0)
            for y in 0..<dimension { for x in 0..<dimension {
                let expected=dimension==16 ? 188 : Int(checkerBytes[(y*256+x)*4])
                maxError=max(maxError,abs(Int(pixels[(y*dimension+x)*4])-expected))
            }}
            precondition(maxError<=2, "Refracted footprint filtering regression")
            print("PASS \(dimension==16 ? "16:1 compression" : "1:1 sharpness") checker: max byte error=\(maxError)")
        }
    }
}
