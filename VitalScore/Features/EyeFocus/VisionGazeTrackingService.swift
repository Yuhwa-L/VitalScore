import Foundation
import AVFoundation
import Vision
import Combine
import CoreGraphics
import os

private let log = Logger(subsystem: "com.vitalscore.app", category: "vision-gaze")

enum CameraPermissionState {
    case unknown
    case granted
    case denied
    case restricted
}

@MainActor
final class VisionGazeTrackingService: NSObject, ObservableObject {
    @Published private(set) var latestGazePoint: CGPoint?
    @Published private(set) var leftEyeBlink: Float = 0
    @Published private(set) var rightEyeBlink: Float = 0
    @Published private(set) var isTracking = false
    @Published private(set) var permissionState: CameraPermissionState = .unknown
    @Published private(set) var framesReceived: Int = 0
    @Published private(set) var facesDetected: Int = 0
    @Published private(set) var lastError: String?
    @Published private(set) var faceCenterInFrame: CGPoint = CGPoint(x: 0.5, y: 0.5)
    @Published private(set) var faceAreaRatio: CGFloat = 0
    @Published private(set) var faceQualityGood: Bool = false

    var onGazeUpdate: ((CGPoint, Float, Float, Bool) -> Void)?

    nonisolated(unsafe) let session = AVCaptureSession()
    nonisolated let processingQueue = DispatchQueue(label: "com.vitalscore.vision.gaze", qos: .userInitiated)
    nonisolated(unsafe) private let landmarksRequest: VNDetectFaceLandmarksRequest = {
        let request = VNDetectFaceLandmarksRequest()
        request.revision = VNDetectFaceLandmarksRequestRevision3
        return request
    }()

    private var configured = false

    override init() {
        super.init()
        refreshPermissionState()
    }

    nonisolated static var isSupported: Bool {
        Self.pickCamera() != nil
    }

    nonisolated static func pickCamera() -> AVCaptureDevice? {
        if let cam = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) {
            return cam
        }
        if let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            return cam
        }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInTrueDepthCamera, .builtInDualCamera],
            mediaType: .video,
            position: .unspecified
        )
        if let front = discovery.devices.first(where: { $0.position == .front }) {
            return front
        }
        if let any = discovery.devices.first {
            return any
        }
        return AVCaptureDevice.default(for: .video)
    }

    func refreshPermissionState() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: permissionState = .granted
        case .notDetermined: permissionState = .unknown
        case .denied: permissionState = .denied
        case .restricted: permissionState = .restricted
        @unknown default: permissionState = .unknown
        }
    }

    func requestPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            permissionState = .granted
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            permissionState = granted ? .granted : .denied
            log.info("Camera permission requested → granted=\(granted, privacy: .public)")
            return granted
        case .denied:
            permissionState = .denied
            return false
        case .restricted:
            permissionState = .restricted
            return false
        @unknown default:
            permissionState = .unknown
            return false
        }
    }

    enum StartResult {
        case ok
        case permissionDenied
        case noCamera(String)
    }

    func start() async -> StartResult {
        let granted = await requestPermission()
        guard granted else {
            lastError = "Camera permission denied"
            log.error("Cannot start: permission \(String(describing: self.permissionState), privacy: .public)")
            return .permissionDenied
        }
        configureSessionIfNeeded()
        if session.inputs.isEmpty {
            let msg = lastError ?? "No camera device."
            lastError = msg
            return .noCamera(msg)
        }
        startSessionAsync()
        return .ok
    }

    func stop() {
        let s = session
        processingQueue.async {
            if s.isRunning { s.stopRunning() }
        }
        isTracking = false
        latestGazePoint = nil
    }

    private func startSessionAsync() {
        let s = session
        processingQueue.async {
            guard !s.isRunning else { return }
            s.startRunning()
            log.info("AVCaptureSession started: running=\(s.isRunning, privacy: .public)")
        }
    }

    private func configureSessionIfNeeded() {
        guard !configured else { return }
        configured = true

        let allDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInTrueDepthCamera, .builtInDualCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
        log.info("Discovered \(allDevices.count, privacy: .public) video device(s): \(allDevices.map { $0.localizedName }.joined(separator: ", "), privacy: .public)")

        session.beginConfiguration()
        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        } else {
            session.sessionPreset = .high
        }

        guard let device = Self.pickCamera() else {
            session.commitConfiguration()
            lastError = "No camera device. In Simulator, set Device → Camera to your Mac camera."
            log.error("No camera device available")
            return
        }
        log.info("Selected camera: \(device.localizedName, privacy: .public) position=\(String(describing: device.position), privacy: .public)")

        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            session.commitConfiguration()
            lastError = "Cannot add camera input"
            log.error("Cannot add camera input")
            return
        }
        session.addInput(input)

        configureFrameRate(for: device)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: processingQueue)
        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        if let connection = output.connection(with: .video) {
            if #available(iOS 17.0, *) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
            } else if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }

        session.commitConfiguration()
        log.info("Session configured")
    }

    private func configureFrameRate(for device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            let targetFPS: Double = 30
            let supported = device.activeFormat.videoSupportedFrameRateRanges.contains {
                $0.minFrameRate <= targetFPS && targetFPS <= $0.maxFrameRate
            }
            if supported {
                let duration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
                device.activeVideoMinFrameDuration = duration
                device.activeVideoMaxFrameDuration = duration
            }
            if device.isSubjectAreaChangeMonitoringEnabled == false {
                device.isSubjectAreaChangeMonitoringEnabled = true
            }
        } catch {
            log.error("Camera frame-rate configuration failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension VisionGazeTrackingService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        processPixelBufferOnQueue(pixelBuffer)
    }

    nonisolated private func processPixelBufferOnQueue(_ pixelBuffer: CVPixelBuffer) {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([landmarksRequest])
        } catch {
            log.error("Vision perform error: \(error.localizedDescription, privacy: .public)")
            return
        }

        let faces = (landmarksRequest.results) ?? []
        let face = Self.bestFace(from: faces)
        let faceCount = faces.count

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.framesReceived += 1
            self.facesDetected = faceCount
        }

        guard let face else {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isTracking = false
                self.faceAreaRatio = 0
                self.faceQualityGood = false
                self.onGazeUpdate?(self.latestGazePoint ?? CGPoint(x: 0.5, y: 0.5), 0, 0, false)
            }
            return
        }

        let result = Self.processFace(face)
        let faceCenter = CGPoint(x: face.boundingBox.midX, y: 1 - face.boundingBox.midY)
        let faceArea = face.boundingBox.width * face.boundingBox.height
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.latestGazePoint = result.gazePoint
            self.leftEyeBlink = result.leftBlink
            self.rightEyeBlink = result.rightBlink
            self.isTracking = result.valid
            self.faceCenterInFrame = faceCenter
            self.faceAreaRatio = faceArea
            self.faceQualityGood = result.valid
            self.onGazeUpdate?(result.gazePoint, result.leftBlink, result.rightBlink, result.valid)
        }
    }

    private struct GazeResult: Sendable {
        let gazePoint: CGPoint
        let leftBlink: Float
        let rightBlink: Float
        let valid: Bool
    }

    nonisolated private static func processFace(_ face: VNFaceObservation) -> GazeResult {
        guard let landmarks = face.landmarks,
              let leftEye = landmarks.leftEye,
              let rightEye = landmarks.rightEye
        else {
            return GazeResult(gazePoint: CGPoint(x: 0.5, y: 0.5), leftBlink: 0, rightBlink: 0, valid: false)
        }

        let leftRel: CGPoint
        let rightRel: CGPoint

        if let leftPupil = landmarks.leftPupil, leftPupil.pointCount > 0,
           let rightPupil = landmarks.rightPupil, rightPupil.pointCount > 0 {
            leftRel = pupilRelativeInEye(pupil: leftPupil, eye: leftEye)
            rightRel = pupilRelativeInEye(pupil: rightPupil, eye: rightEye)
        } else {
            leftRel = CGPoint(x: 0.5, y: 0.5)
            rightRel = CGPoint(x: 0.5, y: 0.5)
        }

        let avgX = (leftRel.x + rightRel.x) / 2
        let avgY = (leftRel.y + rightRel.y) / 2

        let stretch: CGFloat = 1 / 0.4
        let centeredX = (avgX - 0.5) * stretch
        let centeredY = (avgY - 0.5) * stretch
        let screenX = max(0, min(1, 0.5 + centeredX))
        let screenY = max(0, min(1, 0.5 - centeredY))

        let leftEAR = eyeAspectRatio(leftEye)
        let rightEAR = eyeAspectRatio(rightEye)
        let leftBlink = Float(max(0, min(1, (0.3 - leftEAR) / 0.2)))
        let rightBlink = Float(max(0, min(1, (0.3 - rightEAR) / 0.2)))

        return GazeResult(
            gazePoint: CGPoint(x: screenX, y: screenY),
            leftBlink: leftBlink,
            rightBlink: rightBlink,
            valid: faceQualityIsUsable(face)
        )
    }

    nonisolated static func bestFace(from faces: [VNFaceObservation]) -> VNFaceObservation? {
        faces.max { lhs, rhs in
            faceSelectionScore(lhs) < faceSelectionScore(rhs)
        }
    }

    nonisolated static func faceSelectionScore(_ face: VNFaceObservation) -> CGFloat {
        let bounds = face.boundingBox
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let centerPenalty = hypot(center.x - 0.5, center.y - 0.5)
        let area = bounds.width * bounds.height
        return area * 4 - centerPenalty + CGFloat(face.confidence) * 0.2
    }

    nonisolated private static func faceQualityIsUsable(_ face: VNFaceObservation) -> Bool {
        let bounds = face.boundingBox
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let centerOffset = hypot(center.x - 0.5, center.y - 0.5)
        let area = bounds.width * bounds.height
        return face.confidence >= 0.35
            && area >= 0.035
            && centerOffset <= 0.42
    }

    nonisolated private static func pupilRelativeInEye(pupil: VNFaceLandmarkRegion2D, eye: VNFaceLandmarkRegion2D) -> CGPoint {
        let pupilPoint = pupil.normalizedPoints[0]
        let eyePoints = eye.normalizedPoints
        let xs = eyePoints.map { $0.x }
        let ys = eyePoints.map { $0.y }
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 1
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 1
        let width = max(0.0001, maxX - minX)
        let height = max(0.0001, maxY - minY)
        let relX = (pupilPoint.x - minX) / width
        let relY = (pupilPoint.y - minY) / height
        return CGPoint(x: CGFloat(relX), y: CGFloat(relY))
    }

    nonisolated private static func eyeAspectRatio(_ eye: VNFaceLandmarkRegion2D) -> CGFloat {
        let points = eye.normalizedPoints
        let xs = points.map { $0.x }
        let ys = points.map { $0.y }
        let width = (xs.max() ?? 0) - (xs.min() ?? 0)
        let height = (ys.max() ?? 0) - (ys.min() ?? 0)
        return CGFloat(height / max(width, 0.0001))
    }
}
