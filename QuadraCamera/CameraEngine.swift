import AVFoundation
import CoreImage

/// All session mutations happen on cameraQueue. Delivered CIImages retain their
/// pixel buffers; the preview store replaces stale frames instead of queuing them.
final class CameraEngine: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let cameraQueue = DispatchQueue(label: "quadra.camera", qos: .userInitiated)
    private let frameQueue = DispatchQueue(label: "quadra.frames", qos: .userInteractive)
    private let video = AVCaptureVideoDataOutput()
    private let photo = AVCapturePhotoOutput()
    private let audio = AVCaptureAudioDataOutput()
    private var microphone: AVCaptureDeviceInput?
    private var input: AVCaptureDeviceInput?
    private var photoCompletion: ((Result<CIImage, Error>) -> Void)?
    private var configured = false
    private var observers: [NSObjectProtocol] = []
    var onFrame: ((CIImage, Float, CMTime) -> Void)?
    var onAudio: ((CMSampleBuffer) -> Void)?
    var onStatus: ((String?) -> Void)?
    private var tangentHalfFOV: Float = 0.7
    private let geometryLock = NSLock()

    override init() {
        super.init()
        observers.append(NotificationCenter.default.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: nil) { [weak self] note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? Error
            self?.onStatus?(error?.localizedDescription ?? "카메라를 다시 시작해 주세요.")
        })
        observers.append(NotificationCenter.default.addObserver(forName: .AVCaptureSessionWasInterrupted, object: session, queue: nil) { [weak self] _ in
            self?.onStatus?("다른 앱에서 카메라를 사용 중입니다. 잠시 후 다시 시작해 주세요.")
        })
        observers.append(NotificationCenter.default.addObserver(forName: .AVCaptureSessionInterruptionEnded, object: session, queue: nil) { [weak self] _ in
            self?.start()
        })
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func start() {
        cameraQueue.async { [weak self] in
            guard let self else { return }
            do {
                if !configured { try configure() }
                if !session.isRunning { session.startRunning() }
                onStatus?(nil)
            } catch { onStatus?(error.localizedDescription) }
        }
    }

    func stop() {
        cameraQueue.async { [weak self] in self?.session.stopRunning() }
    }

    func setMicrophone(enabled: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void,Error>) in
            cameraQueue.async {
                self.session.beginConfiguration()
                defer { self.session.commitConfiguration() }
                do {
                    if enabled && self.microphone == nil {
                        guard let device=AVCaptureDevice.default(for: .audio) else { throw GlassError.message("마이크를 사용할 수 없습니다.") }
                        let input=try AVCaptureDeviceInput(device: device)
                        guard self.session.canAddInput(input), self.session.canAddOutput(self.audio) else { throw GlassError.message("마이크를 연결하지 못했습니다.") }
                        self.session.addInput(input); self.session.addOutput(self.audio)
                        self.audio.setSampleBufferDelegate(self,queue: self.frameQueue)
                        self.microphone=input
                    } else if !enabled, let input=self.microphone {
                        self.session.removeOutput(self.audio); self.session.removeInput(input)
                        self.microphone=nil
                    }
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        try installCamera(position: .back)
        video.alwaysDiscardsLateVideoFrames = true
        video.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        video.setSampleBufferDelegate(self, queue: frameQueue)
        guard session.canAddOutput(video), session.canAddOutput(photo) else {
            throw GlassError.message("카메라 출력을 연결하지 못했습니다.")
        }
        session.addOutput(video)
        session.addOutput(photo)
        photo.maxPhotoQualityPrioritization = .quality
        setConnections()
        configured = true
    }

    private func installCamera(position: AVCaptureDevice.Position) throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw GlassError.message("사용 가능한 카메라가 없습니다.")
        }
        let newInput = try AVCaptureDeviceInput(device: device)
        let previous = input
        if let previous { session.removeInput(previous) }
        guard session.canAddInput(newInput) else {
            if let previous, session.canAddInput(previous) { session.addInput(previous) }
            throw GlassError.message("카메라를 전환하지 못했습니다.")
        }
        session.addInput(newInput)
        input = newInput
        // Sensor long edge becomes portrait vertical. Preview and still both use
        // a centered 3:4 crop. This is estimated geometry, recorded in metadata.
        geometryLock.lock()
        tangentHalfFOV = tan(device.activeFormat.videoFieldOfView * .pi / 360)
        geometryLock.unlock()
    }

    private func setConnections() {
        for output in [video as AVCaptureOutput, photo as AVCaptureOutput] {
            guard let connection = output.connection(with: .video) else { continue }
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = input?.device.position == .front
            }
            if connection.isVideoStabilizationSupported { connection.preferredVideoStabilizationMode = .off }
        }
        if let largest = input?.device.activeFormat.supportedMaxPhotoDimensions.max(by: {
            Int64($0.width)*Int64($0.height) < Int64($1.width)*Int64($1.height)
        }) {
            // Prefer 12 MP when available, avoiding a needless 48 MP memory spike.
            let dimensions = input?.device.activeFormat.supportedMaxPhotoDimensions.first(where: {
                Int64($0.width)*Int64($0.height) >= 12_000_000 && Int64($0.width)*Int64($0.height) <= 13_000_000
            }) ?? largest
            photo.maxPhotoDimensions = dimensions
        }
    }

    func flip() {
        cameraQueue.async { [weak self] in
            guard let self, configured, photoCompletion == nil else { return }
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            do {
                try installCamera(position: input?.device.position == .back ? .front : .back)
                setConnections()
                onStatus?(nil)
            } catch { onStatus?(error.localizedDescription) }
        }
    }

    func focus(at point: CGPoint) {
        cameraQueue.async { [weak self] in
            guard let device = self?.input?.device else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                let mirrored = device.position == .front ? 1-point.x : point.x
                let sensorPoint = CGPoint(x: point.y, y: 1-mirrored)
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = sensorPoint
                    if device.isFocusModeSupported(.autoFocus) { device.focusMode = .autoFocus }
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = sensorPoint
                    if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                }
            } catch { self?.onStatus?(error.localizedDescription) }
        }
    }

    func capture(_ completion: @escaping (Result<CIImage, Error>) -> Void) {
        cameraQueue.async { [weak self] in
            guard let self, configured, session.isRunning, photoCompletion == nil else {
                completion(.failure(GlassError.message("카메라가 준비되지 않았습니다.")))
                return
            }
            photoCompletion = completion
            let settings = AVCapturePhotoSettings()
            settings.maxPhotoDimensions = photo.maxPhotoDimensions
            settings.photoQualityPrioritization = .quality
            photo.capturePhoto(with: settings, delegate: self)
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output === audio { onAudio?(sampleBuffer); return }
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // Read the session-owned geometry on its queue, retaining only the latest
        // camera buffer at the consumer. No full-frame CPU readback.
        geometryLock.lock()
        let fov = tangentHalfFOV
        geometryLock.unlock()
        onFrame?(CIImage(cvPixelBuffer: buffer), fov, CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto captured: AVCapturePhoto, error: Error?) {
        let result: Result<CIImage, Error>
        if let error { result = .failure(error) }
        else if let data = captured.fileDataRepresentation(),
                let image = CIImage(data: data, options: [.applyOrientationProperty: true]) { result = .success(image) }
        else { result = .failure(GlassError.message("원본 사진을 읽지 못했습니다.")) }
        cameraQueue.async { [weak self] in
            self?.photoCompletion?(result)
            self?.photoCompletion = nil
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        guard let error else { return }
        cameraQueue.async { [weak self] in
            self?.photoCompletion?(.failure(error))
            self?.photoCompletion = nil
        }
    }
}
