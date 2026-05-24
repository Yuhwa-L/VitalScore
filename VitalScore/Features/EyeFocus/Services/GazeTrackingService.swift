import Foundation
import ARKit
import Combine
import simd

struct EyeRaySnapshot: Equatable {
    let leftEyeCamera: SIMD3<Float>
    let rightEyeCamera: SIMD3<Float>
    let lookAtCamera: SIMD3<Float>
    let leftHitNormalized: CGPoint
    let rightHitNormalized: CGPoint
    let lookAtNormalized: CGPoint
    let eyeTransformNormalized: CGPoint
    let combinedNormalized: CGPoint
    let rayDisagreement: CGFloat

    static let zero = EyeRaySnapshot(
        leftEyeCamera: .zero,
        rightEyeCamera: .zero,
        lookAtCamera: .zero,
        leftHitNormalized: CGPoint(x: 0.5, y: 0.5),
        rightHitNormalized: CGPoint(x: 0.5, y: 0.5),
        lookAtNormalized: CGPoint(x: 0.5, y: 0.5),
        eyeTransformNormalized: CGPoint(x: 0.5, y: 0.5),
        combinedNormalized: CGPoint(x: 0.5, y: 0.5),
        rayDisagreement: 0
    )
}

@MainActor
final class GazeTrackingService: NSObject, ObservableObject {
    @Published private(set) var latestGazePoint: CGPoint?
    @Published private(set) var leftEyeBlink: Float = 0
    @Published private(set) var rightEyeBlink: Float = 0
    @Published private(set) var isTracking = false
    @Published private(set) var faceCenterInFrame: CGPoint = CGPoint(x: 0.5, y: 0.5)
    @Published private(set) var faceDistanceM: Float = 0
    @Published private(set) var latestFaceTransformInCamera: simd_float4x4 = matrix_identity_float4x4
    @Published private(set) var latestEyeRays: EyeRaySnapshot = .zero

    var onGazeUpdate: ((_ gazePointNormalized: CGPoint, _ leftBlink: Float, _ rightBlink: Float, _ valid: Bool) -> Void)?

    private weak var arSession: ARSession?

    static let screenWidthM: Float = 0.067
    static let screenHeightM: Float = 0.144
    static let cameraOffsetYM: Float = 0.010

    nonisolated static var isSupported: Bool {
        ARFaceTrackingConfiguration.isSupported
    }

    func attach(session: ARSession) {
        self.arSession = session
        session.delegate = self
    }

    func detach() {
        arSession?.delegate = nil
        arSession = nil
        isTracking = false
        latestGazePoint = nil
    }

    static func rayPlaneIntersect(origin: SIMD3<Float>, target: SIMD3<Float>) -> SIMD2<Float> {
        let dz = target.z - origin.z
        if abs(dz) < 1e-6 {
            return SIMD2(origin.x, origin.y)
        }
        let t = -origin.z / dz
        return SIMD2(
            origin.x + t * (target.x - origin.x),
            origin.y + t * (target.y - origin.y)
        )
    }

    static func metersToNormalizedScreen(_ hitM: SIMD2<Float>) -> CGPoint {
        let normX = (hitM.x + screenWidthM / 2) / screenWidthM
        let normY = (-hitM.y - cameraOffsetYM) / screenHeightM
        return CGPoint(x: CGFloat(normX), y: CGFloat(normY))
    }

    static func isPlausibleScreenPoint(_ point: CGPoint) -> Bool {
        point.x.isFinite && point.y.isFinite
            && point.x > -0.75 && point.x < 1.75
            && point.y > -0.75 && point.y < 1.75
    }

    static func normalizedDistance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }

    private func gazeRays(
        faceAnchor: ARFaceAnchor,
        cameraTransform: simd_float4x4
    ) -> EyeRaySnapshot {
        let invCamera = simd_inverse(cameraTransform)

        let lookAtFace = SIMD4<Float>(faceAnchor.lookAtPoint, 1)
        let lookAtWorld = faceAnchor.transform * lookAtFace
        let lookAtCamera4 = invCamera * lookAtWorld
        let lookAtCamera = SIMD3<Float>(lookAtCamera4.x, lookAtCamera4.y, lookAtCamera4.z)

        let leftEyeWorld = faceAnchor.transform * faceAnchor.leftEyeTransform.columns.3
        let leftEyeCamera4 = invCamera * leftEyeWorld
        let leftEyeCamera = SIMD3<Float>(leftEyeCamera4.x, leftEyeCamera4.y, leftEyeCamera4.z)

        let rightEyeWorld = faceAnchor.transform * faceAnchor.rightEyeTransform.columns.3
        let rightEyeCamera4 = invCamera * rightEyeWorld
        let rightEyeCamera = SIMD3<Float>(rightEyeCamera4.x, rightEyeCamera4.y, rightEyeCamera4.z)

        let leftHitM = Self.rayPlaneIntersect(origin: leftEyeCamera, target: lookAtCamera)
        let rightHitM = Self.rayPlaneIntersect(origin: rightEyeCamera, target: lookAtCamera)
        let avgHitM = SIMD2((leftHitM.x + rightHitM.x) / 2, (leftHitM.y + rightHitM.y) / 2)
        let lookAtNormalized = Self.metersToNormalizedScreen(avgHitM)

        let leftHitNormalized = Self.metersToNormalizedScreen(leftHitM)
        let rightHitNormalized = Self.metersToNormalizedScreen(rightHitM)

        return EyeRaySnapshot(
            leftEyeCamera: leftEyeCamera,
            rightEyeCamera: rightEyeCamera,
            lookAtCamera: lookAtCamera,
            leftHitNormalized: leftHitNormalized,
            rightHitNormalized: rightHitNormalized,
            lookAtNormalized: lookAtNormalized,
            eyeTransformNormalized: lookAtNormalized,
            combinedNormalized: lookAtNormalized,
            rayDisagreement: Self.normalizedDistance(leftHitNormalized, rightHitNormalized)
        )
    }
}

extension GazeTrackingService: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        let faceAnchor = anchors.compactMap { $0 as? ARFaceAnchor }.first
        let cameraTransform = session.currentFrame?.camera.transform
        Task { @MainActor in
            self.handleUpdate(faceAnchor: faceAnchor, cameraTransform: cameraTransform)
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.isTracking = false
            self.latestGazePoint = nil
            self.onGazeUpdate?(CGPoint(x: 0.5, y: 0.5), 0, 0, false)
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor in
            self.isTracking = false
        }
    }

    @MainActor
    private func handleUpdate(faceAnchor: ARFaceAnchor?, cameraTransform: simd_float4x4?) {
        guard let faceAnchor, let cameraTransform else {
            isTracking = false
            onGazeUpdate?(latestGazePoint ?? CGPoint(x: 0.5, y: 0.5), 0, 0, false)
            return
        }

        let leftBlink = (faceAnchor.blendShapes[.eyeBlinkLeft] as? Float) ?? 0
        let rightBlink = (faceAnchor.blendShapes[.eyeBlinkRight] as? Float) ?? 0

        let rays = gazeRays(faceAnchor: faceAnchor, cameraTransform: cameraTransform)
        let normalizedPoint = rays.combinedNormalized
        latestEyeRays = rays

        let invCamera = simd_inverse(cameraTransform)
        let faceInCamera = simd_mul(invCamera, faceAnchor.transform)
        latestFaceTransformInCamera = faceInCamera

        let t = faceInCamera.columns.3
        faceDistanceM = abs(t.z)
        let halfFovX: Float = 0.18
        let halfFovY: Float = 0.24
        let fx = max(0, min(1, (t.x / halfFovX + 1) / 2))
        let fy = max(0, min(1, (-t.y / halfFovY + 1) / 2))
        faceCenterInFrame = CGPoint(x: CGFloat(fx), y: CGFloat(fy))

        latestGazePoint = normalizedPoint
        leftEyeBlink = leftBlink
        rightEyeBlink = rightBlink
        let isPlausible = Self.isPlausibleScreenPoint(normalizedPoint)
        let valid = faceAnchor.isTracked && isPlausible
        isTracking = valid

        onGazeUpdate?(normalizedPoint, leftBlink, rightBlink, valid)
    }
}
