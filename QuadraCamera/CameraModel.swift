import SwiftUI
import AVFoundation
import Photos
import CoreImage
import Observation

struct PreviewFrame {
    let image: CIImage
    let tangentHalfFOV: Float
    let aspect: Float
}

struct RenderSnapshot {
    let material: GlassMaterial
    let tangentHalfFOV: Float
    let frame: CIImage
    let aspect: Float
}

/// One pending image, one in-flight command. Also records the exact material
/// submitted to the display, which is the shutter's immutable snapshot.
final class PreviewStore: @unchecked Sendable {
    private let lock = NSLock()
    private var frame: PreviewFrame?
    private var material: GlassMaterial
    private var original = false
    private var submitted: RenderSnapshot?
    private var acceptsCamera = true
    init(material: GlassMaterial) { self.material = material }
    @discardableResult func setFrame(_ image: CIImage, fov: Float, camera: Bool = false, aspect: Float = 0.75) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if camera && !acceptsCamera { return false }
        frame = PreviewFrame(image: image, tangentHalfFOV: fov, aspect: aspect)
        return true
    }
    func setCameraEnabled(_ enabled: Bool) {
        lock.lock(); defer { lock.unlock() }; acceptsCamera = enabled
    }
    func update(_ material: GlassMaterial, original: Bool) {
        lock.lock(); defer { lock.unlock() }
        self.material = material; self.original = original
    }
    func pending() -> (RenderSnapshot, Bool)? {
        lock.lock(); defer { lock.unlock() }
        guard let frame else { return nil }
        return (RenderSnapshot(material: material, tangentHalfFOV: frame.tangentHalfFOV, frame: frame.image, aspect: frame.aspect), original)
    }
    func markSubmitted(_ snapshot: RenderSnapshot) {
        lock.lock(); defer { lock.unlock() }; submitted = snapshot
    }
    func captureSnapshot() -> RenderSnapshot? {
        lock.lock(); defer { lock.unlock() }; return submitted
    }
}

@MainActor @Observable final class CameraModel {
    enum CaptureMode { case photo, video }
    let base: GlassMaterial
    var material: GlassMaterial
    let store: PreviewStore
    let engine = CameraEngine()
    var cameraMessage: String?
    var errorMessage: String?
    var notice: String?
    var isSample = false
    var isImported = false
    var previewAspect: CGFloat = 0.75
    var isSaving = false
    var captureMode: CaptureMode = .photo
    var isPreparingRecording = false
    var isRecording = false
    var recordingStartedAt: Date?
    var recordingHasAudio = true
    var hasFrame = false
    var showOriginal = false { didSet { store.update(material, original: showOriginal) } }
    var lastPhoto: URL?
    var lastThumbnail: UIImage?
    private var pendingSave: URL?
    private var persistTask: Task<Void, Never>?
    private var recordingTask: Task<Void, Never>?
    private let recorder: VideoRecorder
    private let renderQueue = DispatchQueue(label: "quadra.capture", qos: .userInitiated)
    private let shaderURL: URL
    private var didApplyLaunchMode = false

    init() throws {
        guard let materialURL = Bundle.main.url(forResource: "quadra", withExtension: "json"),
              let shader = Bundle.main.url(forResource: "Quadra", withExtension: "metal") else {
            throw GlassError.message("앱의 유리 재질 파일이 없습니다.")
        }
        shaderURL = shader
        recorder = VideoRecorder(shaderURL: shader)
        base = try GlassMaterial.load(from: materialURL)
        var restored = base
        if let data = UserDefaults.standard.data(forKey: "glass-overrides"),
           let overrides = try? JSONDecoder().decode(SavedOverrides.self, from: data),
           overrides.baseHash == base.hash {
            for (key,value) in overrides.values { restored[key] = value }
            restored.pattern = overrides.pattern ?? .quadra
            if (try? restored.validate()) == nil { restored = base }
        }
        material = restored
        store = PreviewStore(material: restored)
        let store = store
        let recorder = recorder
        engine.onFrame = { [weak self] image, fov, time in
            guard store.setFrame(image, fov: fov, camera: true) else { return }
            if let (snapshot,_) = store.pending() {
                recorder.append(image: image,material: snapshot.material,fov: fov,time: time)
            }
            Task { @MainActor [weak self] in
                guard let self, !self.hasFrame else { return }; self.hasFrame = true
            }
        }
        engine.onAudio = { recorder.appendAudio($0) }
        recorder.onFailure = { [weak self] _ in Task { @MainActor in self?.finishRecording() } }
        engine.onStatus = { [weak self] message in Task { @MainActor in
            guard let self else { return }
            self.cameraMessage = message
            if message != nil { self.recordingTask?.cancel(); self.finishRecording() }
        } }
        if let path = UserDefaults.standard.string(forKey: "last-photo"), FileManager.default.fileExists(atPath: path) {
            lastPhoto = URL(fileURLWithPath: path)
            lastThumbnail = Self.thumbnail(lastPhoto!)
            if lastPhoto?.pathExtension == "mp4", let lastPhoto {
                Task { self.lastThumbnail = await Self.videoThumbnail(lastPhoto) }
            }
        }
    }

    func start() async {
        if !didApplyLaunchMode {
            didApplyLaunchMode = true
            if ProcessInfo.processInfo.arguments.contains("--sample") { loadSample(); return }
        }
        #if targetEnvironment(simulator)
        loadSample()
        #else
        guard !isImported && !isSample else { return }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        var allowed = status == .authorized
        if status == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: .video) }
        if allowed { cameraMessage = nil; engine.start() }
        else { cameraMessage = "카메라 권한이 필요합니다. 설정에서 카메라 접근을 허용해 주세요." }
        #endif
    }

    func stop() {
        recordingTask?.cancel()
        finishRecording()
        engine.stop(); persist()
    }

    func selectCaptureMode(_ mode: CaptureMode) {
        guard !isRecording && !isPreparingRecording && !isSaving else { return }
        captureMode=mode; notice=nil
        if mode == .video && (isSample || isImported) { returnToCamera() }
    }

    func pressShutter() {
        if captureMode == .photo { capture() }
        else if isRecording { finishRecording() }
        else { startRecording() }
    }

    private func startRecording() {
        guard !isSaving && !isPreparingRecording && !isRecording && hasFrame && !isSample && !isImported else { return }
        isPreparingRecording=true; notice=nil; showOriginal=false
        recordingTask=Task {
            do {
                var allowed=AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
                if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                    allowed=await AVCaptureDevice.requestAccess(for: .audio)
                }
                try Task.checkCancellation()
                try await engine.setMicrophone(enabled: allowed)
                try Task.checkCancellation()
                let url=FileManager.default.urls(for: .documentDirectory,in: .userDomainMask)[0]
                    .appendingPathComponent("QUADRA-\(UUID().uuidString).mp4")
                try await recorder.start(at: url,audio: allowed)
                recordingHasAudio=allowed; recordingStartedAt=Date()
                isRecording=true; isPreparingRecording=false
                UIApplication.shared.isIdleTimerDisabled=true
                if Task.isCancelled { finishRecording() }
            } catch {
                try? await engine.setMicrophone(enabled: false)
                isPreparingRecording=false
                if !(error is CancellationError) { errorMessage=error.localizedDescription }
            }
        }
    }

    func finishRecording() {
        guard isRecording else { return }
        isRecording=false; recordingStartedAt=nil; isSaving=true
        UIApplication.shared.isIdleTimerDisabled=false
        let background=UIApplication.shared.beginBackgroundTask(withName: "Finish QUADRA video")
        Task {
            defer { if background != .invalid { UIApplication.shared.endBackgroundTask(background) } }
            do {
                let result=try await recorder.finish()
                try? await engine.setMicrophone(enabled: false)
                lastPhoto=result.url; lastThumbnail=await Self.videoThumbnail(result.url)
                UserDefaults.standard.set(result.url.path,forKey: "last-photo")
                pendingSave=result.url
                #if DEBUG
                let record: [String:Any] = ["file":result.url.lastPathComponent,"duration":result.duration,
                    "frames":result.frames,"audioBuffers":result.audioBuffers,"width":1080,"height":1440,
                    "nominalFPS":30,"audioEnabled":recordingHasAudio,"model":material.model]
                if let data=try? JSONSerialization.data(withJSONObject: record,options: [.sortedKeys]) {
                    try? data.write(to: result.url.deletingLastPathComponent().appendingPathComponent("video-validation.json"),options: .atomic)
                }
                #endif
                await saveToPhotos(result.url)
            } catch {
                try? await engine.setMicrophone(enabled: false)
                isSaving=false; errorMessage=error.localizedDescription
            }
        }
    }

    func loadSample(named name: String = "sample-dog") {
        guard !isRecording && !isPreparingRecording else { return }
        captureMode = .photo
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg"),
              let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { return }
        engine.stop()
        store.setCameraEnabled(false)
        isSample = true; isImported = false; hasFrame = true
        previewAspect = name == "sample-dog" ? 1 : 0.75
        store.setFrame(image, fov: 0.7, aspect: Float(previewAspect))
    }

    func importImage(_ data: Data) {
        guard !isRecording && !isPreparingRecording else { return }
        captureMode = .photo
        guard let image = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            errorMessage = "선택한 사진을 읽지 못했습니다."; return
        }
        engine.stop()
        store.setCameraEnabled(false)
        isSample = false; isImported = true; hasFrame = true
        previewAspect = image.extent.width/image.extent.height
        store.setFrame(image, fov: 0.7, aspect: Float(previewAspect))
        cameraMessage = nil
    }

    func returnToCamera() {
        isSample = false; isImported = false; hasFrame = false
        previewAspect = 0.75
        store.setCameraEnabled(true)
        Task { await start() }
    }

    func set(_ key: String, value: Double) {
        var candidate = material
        candidate[key] = Float(value)
        do {
            try candidate.validate()
            material = candidate
            store.update(material, original: showOriginal)
            persistTask?.cancel()
            persistTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }; self?.persist()
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func reset(_ key: String? = nil) {
        if let key { material[key] = base[key] } else { material = base }
        store.update(material, original: showOriginal)
        persist()
    }

    func selectPattern(_ pattern: GlassPattern) {
        material.pattern = pattern
        showOriginal = false
        persist()
    }

    private struct SavedOverrides: Codable {
        let baseHash: String
        let values: [String: Float]
        let pattern: GlassPattern?
    }
    private func persist() {
        let values = Dictionary(uniqueKeysWithValues: material.controls.map { ($0.id,material[$0.id]) })
        if let data = try? JSONEncoder().encode(SavedOverrides(baseHash: base.hash, values: values, pattern: material.pattern)) {
            UserDefaults.standard.set(data, forKey: "glass-overrides")
        }
    }

    func capture() {
        guard !isSaving && !isRecording && !isPreparingRecording, let snapshot = store.captureSnapshot() else { return }
        isSaving = true; notice = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if isSample || isImported { renderAndSave(snapshot.frame, snapshot: snapshot) }
        else {
            engine.capture { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
                    switch result {
                    case .success(let image): self.renderAndSave(image, snapshot: snapshot)
                    case .failure(let error): self.isSaving = false; self.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    private func renderAndSave(_ image: CIImage, snapshot: RenderSnapshot) {
        let shader = shaderURL
        let baseHash = base.hash
        let isSample = isSample
        let validation = ProcessInfo.processInfo.arguments.contains("--device-validation")
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QUADRA-\(UUID().uuidString).jpg")
        renderQueue.async { [weak self] in
            do {
                let start = Date()
                let renderer = try GlassRenderer(shaderURL: shader)
                let cg = try renderer.render(image: image, material: snapshot.material, tangentHalfFOV: snapshot.tangentHalfFOV, aspect: CGFloat(snapshot.aspect))
                let record: [String: Any] = [
                    "baseMaterialHash": baseHash, "effectiveMaterialHash": snapshot.material.hash,
                    "material": String(data: snapshot.material.canonicalData, encoding: .utf8) ?? "",
                    "depthSource": "constant", "depthMeters": snapshot.material.sceneDistance,
                    "geometryQuality": "estimated", "tangentHalfVerticalFOV": snapshot.tangentHalfFOV,
                    "reflectionSource": "synthetic-room-preset-v1", "status": "prototype", "sample": isSample,
                    "width": cg.width, "height": cg.height, "renderSeconds": Date().timeIntervalSince(start)
                ]
                let json = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
                try GlassRenderer.write(cg, to: file, metadata: [
                    kCGImagePropertyExifDictionary as String: [kCGImagePropertyExifUserComment as String: String(data: json, encoding: .utf8)!]
                ])
                #if DEBUG
                if validation {
                    let directory = file.deletingLastPathComponent()
                    try json.write(to: directory.appendingPathComponent("device-validation.json"), options: .atomic)
                    try GlassRenderer.write(cg, to: directory.appendingPathComponent("device-result.jpg"))
                    let original = try renderer.render(image: image, material: snapshot.material, tangentHalfFOV: snapshot.tangentHalfFOV, maxDimension: 1440, mode: 1, aspect: CGFloat(snapshot.aspect))
                    try GlassRenderer.write(original, to: directory.appendingPathComponent("device-original.jpg"))
                }
                #endif
                Task { @MainActor in
                    guard let self else { return }
                    self.lastPhoto = file; self.lastThumbnail = Self.thumbnail(file)
                    UserDefaults.standard.set(file.path, forKey: "last-photo")
                    #if DEBUG
                    if validation {
                        self.isSaving = false; self.notice = "검증 사진 저장 완료"
                        return
                    }
                    #endif
                    self.pendingSave = file
                    await self.saveToPhotos(file)
                }
            } catch {
                Task { @MainActor in self?.isSaving = false; self?.errorMessage = error.localizedDescription }
            }
        }
    }

    func retrySave() {
        guard let pendingSave, !isSaving else { return }
        isSaving = true
        Task { await saveToPhotos(pendingSave) }
    }

    private func saveToPhotos(_ url: URL) async {
        let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard permission == .authorized || permission == .limited else {
            isSaving = false
            errorMessage = "사진 추가 권한이 필요합니다. 결과는 앱에 보관되어 있으므로 최근 사진에서 공유하거나 다시 저장할 수 있습니다."
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: url.pathExtension == "mp4" ? .video : .photo, fileURL: url, options: nil)
            }
            pendingSave = nil; isSaving = false
            notice = url.pathExtension == "mp4" ? "동영상을 사진 앱에 저장했어요" : "사진 앱에 저장했어요"
            UIAccessibility.post(notification: .announcement, argument: notice)
        } catch { isSaving = false; errorMessage = "저장 실패: \(error.localizedDescription)" }
    }

    private static func thumbnail(_ url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 256,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    private static func videoThumbnail(_ url: URL) async -> UIImage? {
        let generator=AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform=true
        generator.maximumSize=CGSize(width: 256,height: 256)
        guard let result=try? await generator.image(at: .zero) else { return nil }
        return UIImage(cgImage: result.image)
    }
}
