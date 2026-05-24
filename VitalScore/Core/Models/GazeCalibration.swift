import Foundation
import CoreGraphics

struct CalibrationTransform: Codable, Equatable {
    enum Kind: String, Codable { case affine, quadratic }

    let kind: Kind
    let xCoeffs: [Double]
    let yCoeffs: [Double]

    static let identity = CalibrationTransform(
        kind: .affine,
        xCoeffs: [0, 1, 0],
        yCoeffs: [0, 0, 1]
    )

    static func basis(for point: CGPoint, kind: Kind) -> [Double] {
        let x = Double(point.x)
        let y = Double(point.y)
        switch kind {
        case .affine:    return [1, x, y]
        case .quadratic: return [1, x, y, x * x, x * y, y * y]
        }
    }

    func apply(_ rawGaze: CGPoint) -> CGPoint {
        let b = Self.basis(for: rawGaze, kind: kind)
        var outX = 0.0
        var outY = 0.0
        for i in 0..<b.count {
            outX += xCoeffs[i] * b[i]
            outY += yCoeffs[i] * b[i]
        }
        return CGPoint(x: outX, y: outY)
    }

    static func solve(rawPoints: [CGPoint], targetPoints: [CGPoint]) -> CalibrationTransform? {
        guard rawPoints.count == targetPoints.count, rawPoints.count >= 3 else { return nil }
        let kind: Kind = rawPoints.count >= 6 ? .quadratic : .affine
        let dim = (kind == .quadratic) ? 6 : 3

        var ata = Array(repeating: Array(repeating: 0.0, count: dim), count: dim)
        var atbx = Array(repeating: 0.0, count: dim)
        var atby = Array(repeating: 0.0, count: dim)

        for i in 0..<rawPoints.count {
            let a = basis(for: rawPoints[i], kind: kind)
            let tx = Double(targetPoints[i].x)
            let ty = Double(targetPoints[i].y)
            for r in 0..<dim {
                atbx[r] += a[r] * tx
                atby[r] += a[r] * ty
                for c in 0..<dim {
                    ata[r][c] += a[r] * a[c]
                }
            }
        }

        guard let xCoef = Self.solveLinearSystem(ata, b: atbx),
              let yCoef = Self.solveLinearSystem(ata, b: atby) else {
            if kind == .quadratic {
                let affineRecords = zip(rawPoints, targetPoints).map { ($0, $1) }
                return solve(rawPoints: affineRecords.map { $0.0 }, targetPoints: affineRecords.map { $0.1 })
            }
            return nil
        }
        return CalibrationTransform(kind: kind, xCoeffs: xCoef, yCoeffs: yCoef)
    }

    func meanResidualNorm(rawPoints: [CGPoint], targetPoints: [CGPoint]) -> Double {
        guard rawPoints.count == targetPoints.count, !rawPoints.isEmpty else { return 0 }
        var sum = 0.0
        for i in 0..<rawPoints.count {
            let mapped = apply(rawPoints[i])
            let dx = Double(mapped.x - targetPoints[i].x)
            let dy = Double(mapped.y - targetPoints[i].y)
            sum += sqrt(dx * dx + dy * dy)
        }
        return sum / Double(rawPoints.count)
    }

    private static func solveLinearSystem(_ matrix: [[Double]], b: [Double]) -> [Double]? {
        let n = matrix.count
        guard b.count == n else { return nil }
        var a = matrix
        for i in 0..<n { a[i].append(b[i]) }

        for col in 0..<n {
            var pivot = col
            for row in (col + 1)..<n {
                if abs(a[row][col]) > abs(a[pivot][col]) { pivot = row }
            }
            if abs(a[pivot][col]) < 1e-10 { return nil }
            if pivot != col { a.swapAt(col, pivot) }

            let p = a[col][col]
            for j in col...n { a[col][j] /= p }

            for row in 0..<n where row != col {
                let factor = a[row][col]
                for j in col...n { a[row][j] -= factor * a[col][j] }
            }
        }
        return (0..<n).map { a[$0][n] }
    }
}

struct CalibrationRecord: Codable, Equatable {
    let targetX: Double
    let targetY: Double
    let rawAvgX: Double
    let rawAvgY: Double
    let sampleCount: Int

    var targetPoint: CGPoint { CGPoint(x: targetX, y: targetY) }
    var rawAvgPoint: CGPoint { CGPoint(x: rawAvgX, y: rawAvgY) }

    init(targetPoint: CGPoint, rawAvgPoint: CGPoint, sampleCount: Int) {
        self.targetX = Double(targetPoint.x); self.targetY = Double(targetPoint.y)
        self.rawAvgX = Double(rawAvgPoint.x); self.rawAvgY = Double(rawAvgPoint.y)
        self.sampleCount = sampleCount
    }
}

struct CalibrationSummary: Codable, Equatable {
    let records: [CalibrationRecord]
    let transform: CalibrationTransform
    let meanResidualNorm: Double
}

enum GazeCalibrator {
    static let targets: [CGPoint] = [
        CGPoint(x: 0.50, y: 0.50),
        CGPoint(x: 0.15, y: 0.20),
        CGPoint(x: 0.50, y: 0.20),
        CGPoint(x: 0.85, y: 0.20),
        CGPoint(x: 0.85, y: 0.50),
        CGPoint(x: 0.85, y: 0.80),
        CGPoint(x: 0.50, y: 0.80),
        CGPoint(x: 0.15, y: 0.80),
        CGPoint(x: 0.15, y: 0.50)
    ]

    static func robustMean(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return CGPoint(x: 0.5, y: 0.5) }
        let xs = points.map { Double($0.x) }
        let ys = points.map { Double($0.y) }
        let mX = median(xs)
        let mY = median(ys)
        let madX = max(0.005, median(xs.map { abs($0 - mX) }))
        let madY = max(0.005, median(ys.map { abs($0 - mY) }))
        let threshold = 2.5
        let inliers = points.filter {
            abs(Double($0.x) - mX) <= threshold * madX
                && abs(Double($0.y) - mY) <= threshold * madY
        }
        let kept = inliers.isEmpty ? points : inliers
        let avgX = kept.map { $0.x }.reduce(0, +) / CGFloat(kept.count)
        let avgY = kept.map { $0.y }.reduce(0, +) / CGFloat(kept.count)
        return CGPoint(x: avgX, y: avgY)
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let n = sorted.count
        return n.isMultiple(of: 2) ? (sorted[n / 2 - 1] + sorted[n / 2]) / 2 : sorted[n / 2]
    }
}
