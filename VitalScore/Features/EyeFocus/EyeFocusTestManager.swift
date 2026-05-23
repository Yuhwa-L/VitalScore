import Foundation
import Combine
import SwiftUI

final class EyeFocusTestManager: ObservableObject {
    enum Phase: Equatable {
        case idle
        case countdown(Int)
        case running
        case finished(EyeFocusTestResult)
    }

    @Published var phase: Phase = .idle
    @Published var dotPosition: CGPoint = CGPoint(x: 0.5, y: 0.5)
    @Published var dotIsTarget = false

    static let testDurationSeconds: TimeInterval = 30.0
    static let reactionWindowSeconds: TimeInterval = 1.5

    private var startTime: Date?
    private var lastColorChangeAt: Date?
    private var colorChangeTimestamps: [Date] = []
    private var tapTimestamps: [Date] = []
    private var hits: [(colorChange: Date, tapDelayMs: Double)] = []
    private var missedTargets: Int = 0
    private var falseTaps: Int = 0

    private var timer: Timer?
    private var movementTimer: Timer?
    private var countdownTimer: Timer?
    private var endTimer: Timer?

    func start() {
        reset()
        phase = .countdown(3)
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if case .countdown(let n) = self.phase {
                if n > 1 {
                    self.phase = .countdown(n - 1)
                } else {
                    self.countdownTimer?.invalidate()
                    self.beginRunning()
                }
            }
        }
    }

    func cancel() {
        invalidateTimers()
        reset()
        phase = .idle
    }

    func recordTap(at time: Date = Date()) {
        guard case .running = phase else { return }
        tapTimestamps.append(time)

        if dotIsTarget, let last = lastColorChangeAt {
            let delay = time.timeIntervalSince(last) * 1000.0
            if delay >= 0 && delay <= Self.reactionWindowSeconds * 1000.0 {
                hits.append((colorChange: last, tapDelayMs: delay))
                dotIsTarget = false
                return
            }
        }
        falseTaps += 1
    }

    private func beginRunning() {
        phase = .running
        startTime = Date()
        moveDot()
        movementTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            self?.moveDot()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: true) { [weak self] _ in
            self?.toggleColor()
        }
        endTimer = Timer.scheduledTimer(withTimeInterval: Self.testDurationSeconds, repeats: false) { [weak self] _ in
            self?.finish()
        }
    }

    private func moveDot() {
        let x = CGFloat.random(in: 0.15...0.85)
        let y = CGFloat.random(in: 0.20...0.75)
        withAnimation(.easeInOut(duration: 0.6)) {
            dotPosition = CGPoint(x: x, y: y)
        }
    }

    private func toggleColor() {
        if dotIsTarget {
            missedTargets += 1
        }
        dotIsTarget = true
        lastColorChangeAt = Date()
        colorChangeTimestamps.append(lastColorChangeAt!)

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reactionWindowSeconds) { [weak self] in
            guard let self = self else { return }
            if self.dotIsTarget, let last = self.lastColorChangeAt, Date().timeIntervalSince(last) >= Self.reactionWindowSeconds {
                self.missedTargets += 1
                self.dotIsTarget = false
            }
        }
    }

    private func finish() {
        invalidateTimers()
        let reactionTimes = hits.map { $0.tapDelayMs }
        let avg = reactionTimes.isEmpty ? 0 : reactionTimes.reduce(0, +) / Double(reactionTimes.count)
        let stdDev = Self.standardDeviation(reactionTimes)
        let score = Self.calculateScore(
            averageReactionMs: avg,
            reactionStdDevMs: stdDev,
            missedTargets: missedTargets,
            falseTaps: falseTaps
        )
        let result = EyeFocusTestResult(
            averageReactionMs: avg,
            reactionStdDevMs: stdDev,
            missedTargets: missedTargets,
            falseTaps: falseTaps,
            eyeFocusScore: score,
            completedAt: Date()
        )
        phase = .finished(result)
    }

    private func reset() {
        startTime = nil
        lastColorChangeAt = nil
        colorChangeTimestamps.removeAll()
        tapTimestamps.removeAll()
        hits.removeAll()
        missedTargets = 0
        falseTaps = 0
        dotIsTarget = false
        dotPosition = CGPoint(x: 0.5, y: 0.5)
    }

    private func invalidateTimers() {
        countdownTimer?.invalidate()
        timer?.invalidate()
        movementTimer?.invalidate()
        endTimer?.invalidate()
        countdownTimer = nil
        timer = nil
        movementTimer = nil
        endTimer = nil
    }

    static func calculateScore(
        averageReactionMs: Double,
        reactionStdDevMs: Double,
        missedTargets: Int,
        falseTaps: Int
    ) -> Double {
        let reactionPenalty = max(0, averageReactionMs - 300) / 8
        let variabilityPenalty = reactionStdDevMs / 15
        let missPenalty = Double(missedTargets) * 8
        let falseTapPenalty = Double(falseTaps) * 5
        let raw = 100 - reactionPenalty - variabilityPenalty - missPenalty - falseTapPenalty
        return min(100, max(0, raw))
    }

    static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let squaredDiffs = values.map { pow($0 - mean, 2) }
        return sqrt(squaredDiffs.reduce(0, +) / Double(values.count))
    }
}
