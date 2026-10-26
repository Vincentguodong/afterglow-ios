import AVFoundation
import CoreImage
import UIKit
import Combine

/// Session configuration is serialized on `queue`; frame work has its own queue.
/// UI-facing methods are called by the main-actor SwiftUI view.
final class CameraService: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {
    enum Status: Equatable { case idle, denied, ready, unavailable, interrupted }
    @Published private(set) var status: Status = .idle
    @Published private(set) var frame: UIImage?
    @Published private(set) var capturing = false
    @Published private(set) var switching = false
    @Published private(set) var isFrontCamera = false
    @Published var error: String?

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "afterglow.camera", qos: .userInitiated)
    private let frameQueue = DispatchQueue(label: "afterglow.viewfinder", qos: .userInitiated)
    private let photoQueue = DispatchQueue(label: "afterglow.capture-processing", qos: .userInitiated)
    private let output = AVCapturePhotoOutput()
    private let video = AVCaptureVideoDataOutput()
    private let renderer = FilmRenderer()
    private let stateLock = NSLock()
    // These values are shared with the frame queue and protected by stateLock.
    private var recipe = FilmRecipe()
    private var previewAspectRatio: CGFloat = 3.0 / 4.0
    private var generation: UInt64 = 0
    private var acceptsFrames = false
    // The remaining capture state belongs exclusively to queue.
    private var activeInput: AVCaptureDeviceInput?
    private var configured = false
    private var desiredRunning = false
    private var requestingPermission = false
    private var requestedZoom: CGFloat = 1
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var pendingCapture: PendingCapture?
    private var processingCaptureID: Int64?
    // lastFrame belongs exclusively to frameQueue.
    private var lastFrame = CMTime.invalid
    private var observers: [NSObjectProtocol] = []

    private struct PendingCapture {
        let id: Int64
        let aspectRatio: CGFloat
        let completion: (Result<Data, Error>) -> Void
        var data: Data?
        var error: Error?
    }
    private enum CameraFailure: LocalizedError {
        case unavailable, cancelled
        var errorDescription: String? {
            switch self {
            case .unavailable: return "相机暂时不可用，请重新开启相机或导入照片。"
            case .cancelled: return "拍摄已取消，请重新拍摄。"
            }
        }
    }

    override init() {
        super.init()
        observers.append(NotificationCenter.default.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                let token = self.invalidateFrames()
                self.cancelPendingCapture(CameraFailure.unavailable)
                self.publish(.interrupted, generation: token)
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { [weak self] _ in
            self?.resumeIfNeeded()
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] notification in
            guard let self else { return }
            let reset = (notification.userInfo?[AVCaptureSessionErrorKey] as? AVError)?.code == .mediaServicesWereReset
            self.queue.async {
                let token = self.invalidateFrames()
                self.cancelPendingCapture(CameraFailure.unavailable)
                if reset && self.desiredRunning { self.configureAndStart() }
                else { self.publish(.unavailable, generation: token, message: CameraFailure.unavailable.localizedDescription) }
            }
        })
    }
    deinit {
        rotationObservation?.invalidate()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func updateRecipe(_ recipe: FilmRecipe) {
        stateLock.lock(); self.recipe = recipe.normalized(); stateLock.unlock()
    }
    /// Pass the width/height of the image area, excluding the film sprockets.
    func setPreviewAspectRatio(_ ratio: CGFloat) {
        guard ratio.isFinite, ratio > 0 else { return }
        stateLock.lock(); previewAspectRatio = min(4, max(0.25, ratio)); stateLock.unlock()
    }
    func start(requestPermission: Bool = false) {
        queue.async {
            self.desiredRunning = true
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: self.configureAndStart()
            case .notDetermined:
                guard requestPermission, !self.requestingPermission else { return }
                self.requestingPermission = true
                AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                    guard let self else { return }
                    self.queue.async {
                        self.requestingPermission = false
                        // A navigation or background transition may have stopped us
                        // while the system permission prompt was on screen.
                        guard self.desiredRunning else { return }
                        if allowed { self.configureAndStart() }
                        else { self.publish(.denied, generation: self.currentGeneration()) }
                    }
                }
            default: self.publish(.denied, generation: self.currentGeneration())
            }
        }
    }
    func stop() {
        // Invalidate queued frame publications immediately, before stopRunning.
        let token = invalidateFrames()
        publish(.idle, generation: token)
        queue.async {
            self.desiredRunning = false
            // A startRunning already in progress may have re-enabled delivery
            // after stop() invalidated it on the calling thread.
            let stoppedGeneration = self.invalidateFrames()
            self.cancelPendingCapture(CameraFailure.cancelled)
            if self.session.isRunning { self.session.stopRunning() }
            self.publish(.idle, generation: stoppedGeneration)
        }
    }
    private func resumeIfNeeded() {
        queue.async { if self.desiredRunning { self.configureAndStart() } }
    }
    private func configureAndStart() {
        guard desiredRunning else { return }
        do {
            if !configured {
                session.beginConfiguration()
                defer { session.commitConfiguration() }
                session.sessionPreset = .photo
                guard let device = cameraDevice(position: .back) else { throw CameraFailure.unavailable }
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else { throw CameraFailure.unavailable }
                session.addInput(input)
                guard session.canAddOutput(output) else { session.removeInput(input); throw CameraFailure.unavailable }
                session.addOutput(output)
                guard session.canAddOutput(video) else {
                    session.removeOutput(output); session.removeInput(input); throw CameraFailure.unavailable
                }
                session.addOutput(video)
                activeInput = input
                video.alwaysDiscardsLateVideoFrames = true
                video.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                video.setSampleBufferDelegate(self, queue: frameQueue)
                configureOutputs(for: device)
                configured = true
            }
            if !session.isRunning { session.startRunning() }
            let running = session.isRunning && !session.isInterrupted
            let token = setFrameDelivery(running)
            publish(running ? .ready : .unavailable, generation: token)
        } catch {
            let token = invalidateFrames()
            publish(.unavailable, generation: token, message: error.localizedDescription)
        }
    }
    private func cameraDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
            ?? (position == .front ? AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) : nil)
    }
    private func configureOutputs(for device: AVCaptureDevice) {
        output.maxPhotoQualityPrioritization = .quality
        // Prefer a regular photo size within this app's 4096 px processing budget.
        // Request only a dimension pair advertised by this device's active format.
        let sizes = device.activeFormat.supportedMaxPhotoDimensions
        let withinBudget = sizes.filter { max($0.width, $0.height) <= 4096 }
        let area: (CMVideoDimensions) -> Int64 = { Int64($0.width) * Int64($0.height) }
        if let size = withinBudget.max(by: { area($0) < area($1) }) ?? sizes.min(by: { area($0) < area($1) }) {
            output.maxPhotoDimensions = size
        }
        for connection in [video.connection(with: .video), output.connection(with: .video)].compactMap({ $0 }) {
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                // Keep saved selfies consistent with the mirrored live preview.
                connection.isVideoMirrored = device.position == .front
            }
            if connection.isVideoStabilizationSupported { connection.preferredVideoStabilizationMode = .off }
        }
        rotationObservation?.invalidate()
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        rotationCoordinator = coordinator
        // We display processed video buffers rather than a preview layer. Both
        // data output and photo output therefore use the capture rotation angle.
        applyRotation(coordinator.videoRotationAngleForHorizonLevelCapture)
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self, weak device] _, change in
            guard let self, let device, let angle = change.newValue else { return }
            self.queue.async {
                guard self.activeInput?.device.uniqueID == device.uniqueID else { return }
                self.applyRotation(angle)
            }
        }
        applyZoom()
    }
    private func applyRotation(_ angle: CGFloat) {
        for connection in [video.connection(with: .video), output.connection(with: .video)].compactMap({ $0 }) {
            if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
        }
    }
    func switchCamera() {
        guard !capturing, !switching, status == .ready else { return }
        switching = true
        let token = invalidateFrames()
        publish(.idle, generation: token)
        queue.async {
            defer { DispatchQueue.main.async { self.switching = false } }
            guard self.desiredRunning, self.pendingCapture == nil, let previous = self.activeInput else { return }
            do {
                let position: AVCaptureDevice.Position = previous.device.position == .back ? .front : .back
                guard let device = self.cameraDevice(position: position) else { throw CameraFailure.unavailable }
                let next = try AVCaptureDeviceInput(device: device)
                self.session.beginConfiguration()
                self.session.removeInput(previous)
                guard self.session.canAddInput(next) else {
                    self.session.addInput(previous)
                    self.session.commitConfiguration()
                    throw CameraFailure.unavailable
                }
                self.session.addInput(next)
                self.activeInput = next
                self.requestedZoom = 1
                self.configureOutputs(for: device)
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.isFrontCamera = position == .front }
                self.configureAndStart()
            } catch {
                self.configureAndStart()
                DispatchQueue.main.async { self.error = error.localizedDescription }
            }
        }
    }
    func setZoom(_ zoom: CGFloat) {
        guard zoom.isFinite else { return }
        queue.async { self.requestedZoom = max(1, zoom); self.applyZoom() }
    }
    private func applyZoom() {
        guard let device = activeInput?.device else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.videoZoomFactor = min(device.maxAvailableVideoZoomFactor, max(device.minAvailableVideoZoomFactor, requestedZoom))
        } catch { DispatchQueue.main.async { self.error = error.localizedDescription } }
    }
    func capture(completion: @escaping (Result<Data, Error>) -> Void) {
        guard !capturing, !switching, status == .ready else { return }
        capturing = true
        queue.async {
            guard self.desiredRunning, self.session.isRunning, !self.session.isInterrupted,
                  self.pendingCapture == nil, self.processingCaptureID == nil else {
                DispatchQueue.main.async { self.capturing = false; completion(.failure(CameraFailure.unavailable)) }
                return
            }
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            settings.photoQualityPrioritization = .quality
            if self.output.maxPhotoDimensions.width > 0, self.output.maxPhotoDimensions.height > 0 {
                settings.maxPhotoDimensions = self.output.maxPhotoDimensions
            }
            settings.flashMode = .off
            self.stateLock.lock(); let ratio = self.previewAspectRatio; self.stateLock.unlock()
            self.pendingCapture = PendingCapture(id: settings.uniqueID, aspectRatio: ratio, completion: completion)
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let id = photo.resolvedSettings.uniqueID
        let data = photo.fileDataRepresentation()
        queue.async {
            guard self.pendingCapture?.id == id else { return }
            self.pendingCapture?.data = data
            self.pendingCapture?.error = error ?? (data == nil ? ImageFailure.unreadable : nil)
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        queue.async {
            guard let request = self.pendingCapture, request.id == resolvedSettings.uniqueID else { return }
            self.pendingCapture = nil
            if let failure = error ?? request.error {
                DispatchQueue.main.async { self.capturing = false; request.completion(.failure(failure)) }
                return
            }
            guard let data = request.data else {
                DispatchQueue.main.async { self.capturing = false; request.completion(.failure(ImageFailure.unreadable)) }
                return
            }
            self.processingCaptureID = request.id
            self.photoQueue.async {
                let result = Result { try autoreleasepool { try Self.framedJPEG(data, aspectRatio: request.aspectRatio) } }
                self.queue.async {
                    guard self.processingCaptureID == request.id else { return }
                    self.processingCaptureID = nil
                    DispatchQueue.main.async { self.capturing = false; request.completion(result) }
                }
            }
        }
    }
    /// Match aspect-fill viewfinder framing, after honoring the photo's EXIF orientation.
    static func framedJPEG(_ data: Data, aspectRatio: CGFloat) throws -> Data {
        let image = try FilmRenderer.decode(data, maxEdge: 4096)
        guard let cg = image.cgImage, aspectRatio.isFinite, aspectRatio > 0 else { throw ImageFailure.unreadable }
        let width = CGFloat(cg.width), height = CGFloat(cg.height)
        let targetWidth = min(width, height * aspectRatio)
        let targetHeight = min(height, width / aspectRatio)
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let rect = CGRect(x: (width - targetWidth) / 2, y: (height - targetHeight) / 2,
                          width: targetWidth, height: targetHeight).integral.intersection(bounds)
        guard let crop = cg.cropping(to: rect), let jpeg = UIImage(cgImage: crop).jpegData(compressionQuality: 0.98) else { throw ImageFailure.rendering }
        return jpeg
    }
    private func cancelPendingCapture(_ failure: Error) {
        if let request = pendingCapture {
            pendingCapture = nil
            DispatchQueue.main.async { self.capturing = false; request.completion(.failure(failure)) }
        }
        // Once capture has finished, processing can complete after a brief app
        // interruption. The resulting photo remains a valid, explicit shutter action.
    }
    private func currentGeneration() -> UInt64 {
        stateLock.lock(); defer { stateLock.unlock() }; return generation
    }
    @discardableResult private func invalidateFrames() -> UInt64 {
        stateLock.lock(); defer { stateLock.unlock() }
        acceptsFrames = false; generation &+= 1; return generation
    }
    private func setFrameDelivery(_ active: Bool) -> UInt64 {
        stateLock.lock(); defer { stateLock.unlock() }
        acceptsFrames = active; generation &+= 1
        frameQueue.async { self.lastFrame = .invalid }
        return generation
    }
    private func publish(_ status: Status, generation token: UInt64, message: String? = nil) {
        DispatchQueue.main.async {
            guard self.currentGeneration() == token else { return }
            self.status = status
            if status != .ready { self.frame = nil }
            if let message { self.error = message }
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        stateLock.lock(); let active = acceptsFrames; let token = generation; let currentRecipe = recipe; stateLock.unlock()
        guard active else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard (!lastFrame.isValid || CMTimeGetSeconds(timestamp - lastFrame) >= 1.0 / 12.0),
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = timestamp
        autoreleasepool {
            if let image = try? renderer.render(CIImage(cvPixelBuffer: buffer), recipe: currentRecipe, maxEdge: 800) {
                DispatchQueue.main.async {
                    self.stateLock.lock(); let current = self.acceptsFrames && self.generation == token; self.stateLock.unlock()
                    if current { self.frame = image }
                }
            }
        }
    }
}
