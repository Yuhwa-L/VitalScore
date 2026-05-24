import Foundation
import CoreMotion
import Combine
import simd

struct MotionSnapshot: Codable, Equatable {
    let rotationRateMag: Double
    let userAccelerationMag: Double
    let gravityX: Double
    let gravityY: Double
    let gravityZ: Double
    let isStable: Bool

    static let zero = MotionSnapshot(
        rotationRateMag: 0,
        userAccelerationMag: 0,
        gravityX: 0,
        gravityY: -1,
        gravityZ: 0,
        isStable: true
    )
}

@MainActor
final class DeviceMotionTracker: ObservableObject {
    @Published private(set) var snapshot: MotionSnapshot = .zero

    static let rotationStabilityThreshold: Double = 0.15
    static let accelStabilityThreshold: Double = 0.10

    nonisolated(unsafe) private let motionManager = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.vitalscore.devicemotion"
        q.maxConcurrentOperationCount = 1
        return q
    }()

    nonisolated var isAvailable: Bool { motionManager.isDeviceMotionAvailable }

    func start() {
        guard motionManager.isDeviceMotionAvailable, !motionManager.isDeviceMotionActive else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let motion else { return }
            let r = motion.rotationRate
            let a = motion.userAcceleration
            let g = motion.gravity
            let rotMag = sqrt(r.x * r.x + r.y * r.y + r.z * r.z)
            let accMag = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
            let stable = rotMag < Self.rotationStabilityThreshold && accMag < Self.accelStabilityThreshold
            let snap = MotionSnapshot(
                rotationRateMag: rotMag,
                userAccelerationMag: accMag,
                gravityX: g.x,
                gravityY: g.y,
                gravityZ: g.z,
                isStable: stable
            )
            Task { @MainActor [weak self] in
                self?.snapshot = snap
            }
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }
}
