import Foundation
import CoreGraphics

final class OneEuroFilter {
    private var minCutoff: Double
    private var beta: Double
    private let dCutoff: Double = 1.0

    private var x: Double = 0
    private var dx: Double = 0
    private var lastTime: TimeInterval = 0
    private var initialized = false

    init(minCutoff: Double = 1.0, beta: Double = 0.007) {
        self.minCutoff = minCutoff
        self.beta = beta
    }

    func filter(_ value: Double, at time: TimeInterval) -> Double {
        guard initialized else {
            x = value
            lastTime = time
            initialized = true
            return value
        }
        let dt = max(1e-6, time - lastTime)
        lastTime = time
        let dxRaw = (value - x) / dt
        let dxAlpha = Self.alphaForCutoff(dCutoff, dt: dt)
        dx = dx + dxAlpha * (dxRaw - dx)
        let cutoff = minCutoff + beta * abs(dx)
        let alpha = Self.alphaForCutoff(cutoff, dt: dt)
        x = x + alpha * (value - x)
        return x
    }

    func reset() {
        initialized = false
        x = 0
        dx = 0
    }

    private static func alphaForCutoff(_ cutoff: Double, dt: TimeInterval) -> Double {
        let tau = 1.0 / (2.0 * .pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }
}

struct OneEuroFilter2D {
    private let xFilter: OneEuroFilter
    private let yFilter: OneEuroFilter

    init(minCutoff: Double = 1.0, beta: Double = 0.007) {
        self.xFilter = OneEuroFilter(minCutoff: minCutoff, beta: beta)
        self.yFilter = OneEuroFilter(minCutoff: minCutoff, beta: beta)
    }

    func filter(_ point: CGPoint, at time: TimeInterval) -> CGPoint {
        CGPoint(
            x: xFilter.filter(Double(point.x), at: time),
            y: yFilter.filter(Double(point.y), at: time)
        )
    }

    func reset() {
        xFilter.reset()
        yFilter.reset()
    }
}
