import Foundation
import simd

struct HeadPoseSnapshot: Codable, Equatable {
    let positionX: Float
    let positionY: Float
    let positionZ: Float
    let yawDeg: Float
    let pitchDeg: Float
    let rollDeg: Float

    init(transformInCamera m: simd_float4x4) {
        self.positionX = m.columns.3.x
        self.positionY = m.columns.3.y
        self.positionZ = m.columns.3.z
        let (yaw, pitch, roll) = Self.eulerDegrees(from: m)
        self.yawDeg = yaw
        self.pitchDeg = pitch
        self.rollDeg = roll
    }

    init(positionX: Float, positionY: Float, positionZ: Float, yawDeg: Float, pitchDeg: Float, rollDeg: Float) {
        self.positionX = positionX; self.positionY = positionY; self.positionZ = positionZ
        self.yawDeg = yawDeg; self.pitchDeg = pitchDeg; self.rollDeg = rollDeg
    }

    static let zero = HeadPoseSnapshot(
        positionX: 0, positionY: 0, positionZ: 0,
        yawDeg: 0, pitchDeg: 0, rollDeg: 0
    )

    private static func eulerDegrees(from m: simd_float4x4) -> (yaw: Float, pitch: Float, roll: Float) {
        let r00 = m.columns.0.x
        let r10 = m.columns.0.y
        let r20 = m.columns.0.z
        let r21 = m.columns.1.z
        let r22 = m.columns.2.z
        let pitch = asin(-r20)
        let yaw: Float
        let roll: Float
        if cos(pitch) > 1e-4 {
            yaw = atan2(r10, r00)
            roll = atan2(r21, r22)
        } else {
            yaw = 0
            roll = atan2(-m.columns.1.x, m.columns.1.y)
        }
        let toDeg: Float = 180.0 / .pi
        return (yaw * toDeg, pitch * toDeg, roll * toDeg)
    }

    func deviation(from baseline: HeadPoseSnapshot) -> Float {
        let dx = positionX - baseline.positionX
        let dy = positionY - baseline.positionY
        let dz = positionZ - baseline.positionZ
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

    func angularDeviationDeg(from baseline: HeadPoseSnapshot) -> Float {
        let dYaw = yawDeg - baseline.yawDeg
        let dPitch = pitchDeg - baseline.pitchDeg
        let dRoll = rollDeg - baseline.rollDeg
        return sqrt(dYaw * dYaw + dPitch * dPitch + dRoll * dRoll)
    }
}
