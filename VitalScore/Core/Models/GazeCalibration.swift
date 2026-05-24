import Foundation
import CoreGraphics

struct CalibrationInput: Codable, Equatable {
    let rawX: Double
    let rawY: Double
    let headPositionX: Double
    let headPositionY: Double
    let headPositionZ: Double
    let headYawDeg: Double
    let headPitchDeg: Double
    let headRollDeg: Double
    let gravityX: Double
    let gravityY: Double
    let gravityZ: Double

    var rawPoint: CGPoint {
        CGPoint(x: rawX, y: rawY)
    }

    init(
        rawGaze: CGPoint,
        headPose: HeadPoseSnapshot = .zero,
        motion: MotionSnapshot = .zero
    ) {
        self.rawX = Double(rawGaze.x)
        self.rawY = Double(rawGaze.y)
        self.headPositionX = Double(headPose.positionX)
        self.headPositionY = Double(headPose.positionY)
        self.headPositionZ = Double(headPose.positionZ)
        self.headYawDeg = Double(headPose.yawDeg)
        self.headPitchDeg = Double(headPose.pitchDeg)
        self.headRollDeg = Double(headPose.rollDeg)
        self.gravityX = motion.gravityX
        self.gravityY = motion.gravityY
        self.gravityZ = motion.gravityZ
    }

    init(
        rawX: Double,
        rawY: Double,
        headPositionX: Double,
        headPositionY: Double,
        headPositionZ: Double,
        headYawDeg: Double,
        headPitchDeg: Double,
        headRollDeg: Double,
        gravityX: Double,
        gravityY: Double,
        gravityZ: Double
    ) {
        self.rawX = rawX
        self.rawY = rawY
        self.headPositionX = headPositionX
        self.headPositionY = headPositionY
        self.headPositionZ = headPositionZ
        self.headYawDeg = headYawDeg
        self.headPitchDeg = headPitchDeg
        self.headRollDeg = headRollDeg
        self.gravityX = gravityX
        self.gravityY = gravityY
        self.gravityZ = gravityZ
    }

    static let neutral = CalibrationInput(rawGaze: CGPoint(x: 0.5, y: 0.5))
}

struct CalibrationSample: Codable, Equatable {
    let targetX: Double
    let targetY: Double
    let input: CalibrationInput

    var targetPoint: CGPoint {
        CGPoint(x: targetX, y: targetY)
    }

    init(targetPoint: CGPoint, input: CalibrationInput) {
        self.targetX = Double(targetPoint.x)
        self.targetY = Double(targetPoint.y)
        self.input = input
    }
}

struct CalibrationTransform: Codable, Equatable {
    enum Kind: String, Codable { case affine, quadratic, poseAware }

    let kind: Kind
    let xCoeffs: [Double]
    let yCoeffs: [Double]
    let featureMeans: [Double]
    let featureScales: [Double]

    static let identity = CalibrationTransform(
        kind: .affine,
        xCoeffs: [0, 1, 0],
        yCoeffs: [0, 0, 1],
        featureMeans: [],
        featureScales: []
    )

    init(
        kind: Kind,
        xCoeffs: [Double],
        yCoeffs: [Double],
        featureMeans: [Double] = [],
        featureScales: [Double] = []
    ) {
        self.kind = kind
        self.xCoeffs = xCoeffs
        self.yCoeffs = yCoeffs
        self.featureMeans = featureMeans
        self.featureScales = featureScales
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case xCoeffs
        case yCoeffs
        case featureMeans
        case featureScales
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        xCoeffs = try container.decode([Double].self, forKey: .xCoeffs)
        yCoeffs = try container.decode([Double].self, forKey: .yCoeffs)
        featureMeans = try container.decodeIfPresent([Double].self, forKey: .featureMeans) ?? []
        featureScales = try container.decodeIfPresent([Double].self, forKey: .featureScales) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(xCoeffs, forKey: .xCoeffs)
        try container.encode(yCoeffs, forKey: .yCoeffs)
        if !featureMeans.isEmpty {
            try container.encode(featureMeans, forKey: .featureMeans)
        }
        if !featureScales.isEmpty {
            try container.encode(featureScales, forKey: .featureScales)
        }
    }

    static func basis(for point: CGPoint, kind: Kind) -> [Double] {
        basis(for: CalibrationInput(rawGaze: point), kind: kind, featureMeans: [], featureScales: [])
    }

    static func basis(
        for input: CalibrationInput,
        kind: Kind,
        featureMeans: [Double],
        featureScales: [Double]
    ) -> [Double] {
        let values = featureValues(for: input, kind: kind)
        let normalized = normalize(values, means: featureMeans, scales: featureScales)
        return [1] + normalized
    }

    static func featureValues(for input: CalibrationInput, kind: Kind) -> [Double] {
        let x = input.rawX
        let y = input.rawY
        switch kind {
        case .affine:
            return [x, y]
        case .quadratic:
            return [x, y, x * x, x * y, y * y]
        case .poseAware:
            return [
                x,
                y,
                x * x,
                x * y,
                y * y,
                input.headPositionX,
                input.headPositionY,
                input.headPositionZ,
                input.headYawDeg,
                input.headPitchDeg,
                input.headRollDeg,
                input.gravityX,
                input.gravityY,
                input.gravityZ,
                x * input.headPositionX,
                y * input.headPositionY,
                x * input.headYawDeg,
                y * input.headPitchDeg
            ]
        }
    }

    private static func normalize(_ values: [Double], means: [Double], scales: [Double]) -> [Double] {
        guard means.count == values.count, scales.count == values.count else {
            return values
        }
        return values.enumerated().map { index, value in
            (value - means[index]) / scales[index]
        }
    }

    func apply(_ rawGaze: CGPoint) -> CGPoint {
        apply(CalibrationInput(rawGaze: rawGaze))
    }

    func apply(_ input: CalibrationInput) -> CGPoint {
        let b = Self.basis(
            for: input,
            kind: kind,
            featureMeans: featureMeans,
            featureScales: featureScales
        )
        guard xCoeffs.count == b.count, yCoeffs.count == b.count else {
            return input.rawPoint
        }
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
        let samples = zip(rawPoints, targetPoints).map {
            CalibrationSample(targetPoint: $0.1, input: CalibrationInput(rawGaze: $0.0))
        }
        return fit(samples: samples, kind: kind, ridgeLambda: 1e-8)
    }

    static func solve(samples: [CalibrationSample]) -> CalibrationTransform? {
        let fitSamples = GazeCalibrator.robustSamples(samples)
        guard fitSamples.count >= 3 else { return nil }

        let grouped = Dictionary(grouping: fitSamples) { sample in
            "\(sample.targetX.rounded(toPlaces: 4)),\(sample.targetY.rounded(toPlaces: 4))"
        }
        let records = grouped.values.map { group -> CalibrationSample in
            let robust = GazeCalibrator.robustMean(group.map { $0.input.rawPoint })
            return CalibrationSample(
                targetPoint: group[0].targetPoint,
                input: CalibrationInput(rawGaze: robust)
            )
        }

        let targetLevelSamples = records.sorted {
            if $0.targetY == $1.targetY { return $0.targetX < $1.targetX }
            return $0.targetY < $1.targetY
        }
        guard targetLevelSamples.count >= 3 else { return nil }

        let candidates: [Kind] = targetLevelSamples.count >= 6 ? [.affine, .quadratic] : [.affine]
        let scored = candidates.compactMap { kind -> (transform: CalibrationTransform, score: Double)? in
            guard let transform = fit(samples: targetLevelSamples, kind: kind, ridgeLambda: 1e-6) else {
                return nil
            }
            let residual = transform.meanResidualNorm(samples: targetLevelSamples)
            guard residual.isFinite else { return nil }
            let complexityPenalty = Double(transform.xCoeffs.count) * 0.0015
            return (transform, residual + complexityPenalty)
        }

        return scored.min { $0.score < $1.score }?.transform
    }

    private static func fit(
        samples: [CalibrationSample],
        kind: Kind,
        ridgeLambda: Double
    ) -> CalibrationTransform? {
        let featureRows = samples.map { featureValues(for: $0.input, kind: kind) }
        guard let featureCount = featureRows.first?.count, featureRows.allSatisfy({ $0.count == featureCount }) else {
            return nil
        }

        let stats = normalizedStats(for: featureRows)
        let rows = featureRows.map { [1] + normalize($0, means: stats.means, scales: stats.scales) }
        let dim = featureCount + 1

        var ata = Array(repeating: Array(repeating: 0.0, count: dim), count: dim)
        var atbx = Array(repeating: 0.0, count: dim)
        var atby = Array(repeating: 0.0, count: dim)

        for i in 0..<samples.count {
            let a = rows[i]
            let tx = samples[i].targetX
            let ty = samples[i].targetY
            for r in 0..<dim {
                atbx[r] += a[r] * tx
                atby[r] += a[r] * ty
                for c in 0..<dim {
                    ata[r][c] += a[r] * a[c]
                }
            }
        }

        if ridgeLambda > 0 {
            for i in 1..<dim {
                ata[i][i] += ridgeLambda
            }
        }

        guard let xCoef = Self.solveLinearSystem(ata, b: atbx),
              let yCoef = Self.solveLinearSystem(ata, b: atby) else {
            return nil
        }
        return CalibrationTransform(
            kind: kind,
            xCoeffs: xCoef,
            yCoeffs: yCoef,
            featureMeans: stats.means,
            featureScales: stats.scales
        )
    }

    func meanResidualNorm(rawPoints: [CGPoint], targetPoints: [CGPoint]) -> Double {
        guard rawPoints.count == targetPoints.count, !rawPoints.isEmpty else { return 0 }
        let samples = zip(rawPoints, targetPoints).map {
            CalibrationSample(targetPoint: $0.1, input: CalibrationInput(rawGaze: $0.0))
        }
        return meanResidualNorm(samples: samples)
    }

    func meanResidualNorm(samples: [CalibrationSample]) -> Double {
        guard !samples.isEmpty else { return 0 }
        var sum = 0.0
        for sample in samples {
            let mapped = apply(sample.input)
            let dx = Double(mapped.x - sample.targetX)
            let dy = Double(mapped.y - sample.targetY)
            sum += sqrt(dx * dx + dy * dy)
        }
        return sum / Double(samples.count)
    }

    func robustResidualNorm(samples: [CalibrationSample]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let residuals = samples.map { sample in
            let mapped = apply(sample.input)
            let dx = Double(mapped.x - sample.targetX)
            let dy = Double(mapped.y - sample.targetY)
            return sqrt(dx * dx + dy * dy)
        }.sorted()
        let keepCount = max(1, Int(ceil(Double(residuals.count) * 0.8)))
        let kept = residuals.prefix(keepCount)
        return kept.reduce(0, +) / Double(keepCount)
    }

    private static func normalizedStats(for rows: [[Double]]) -> (means: [Double], scales: [Double]) {
        guard let featureCount = rows.first?.count, !rows.isEmpty else {
            return ([], [])
        }
        var means = Array(repeating: 0.0, count: featureCount)
        for row in rows {
            for i in 0..<featureCount {
                means[i] += row[i]
            }
        }
        means = means.map { $0 / Double(rows.count) }

        var variances = Array(repeating: 0.0, count: featureCount)
        for row in rows {
            for i in 0..<featureCount {
                let diff = row[i] - means[i]
                variances[i] += diff * diff
            }
        }

        let scales = variances.map { variance in
            let std = sqrt(variance / Double(rows.count))
            return max(std, 1e-4)
        }
        return (means, scales)
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
    let sampleCount: Int
    let baselineHeadPose: HeadPoseSnapshot?

    init(
        records: [CalibrationRecord],
        transform: CalibrationTransform,
        meanResidualNorm: Double,
        sampleCount: Int = 0,
        baselineHeadPose: HeadPoseSnapshot? = nil
    ) {
        self.records = records
        self.transform = transform
        self.meanResidualNorm = meanResidualNorm
        self.sampleCount = sampleCount
        self.baselineHeadPose = baselineHeadPose
    }
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

    static func robustSamples(_ samples: [CalibrationSample]) -> [CalibrationSample] {
        let finiteSamples = samples.filter {
            $0.input.rawX.isFinite && $0.input.rawY.isFinite
        }
        guard finiteSamples.count >= 6 else { return finiteSamples }

        let grouped = Dictionary(grouping: finiteSamples) { sample in
            "\(sample.targetX.rounded(toPlaces: 4)),\(sample.targetY.rounded(toPlaces: 4))"
        }

        var kept: [CalibrationSample] = []
        for group in grouped.values {
            guard group.count >= 4 else {
                kept.append(contentsOf: group)
                continue
            }

            let center = robustMean(group.map { $0.input.rawPoint })
            let distances = group.map {
                hypot($0.input.rawX - Double(center.x), $0.input.rawY - Double(center.y))
            }
            let medianDistance = median(distances)
            let mad = max(0.006, median(distances.map { abs($0 - medianDistance) }))
            let threshold = max(0.045, medianDistance + 3.5 * mad)
            kept.append(contentsOf: group.filter {
                hypot($0.input.rawX - Double(center.x), $0.input.rawY - Double(center.y)) <= threshold
            })
        }

        return kept.count >= 3 ? kept : finiteSamples
    }

    static func meanHeadPose(samples: [CalibrationSample]) -> HeadPoseSnapshot? {
        guard !samples.isEmpty else { return nil }
        let count = Float(samples.count)
        let sum = samples.reduce(
            HeadPoseSnapshot.zero,
            { partial, sample in
                let pose = sample.input
                return HeadPoseSnapshot(
                    positionX: partial.positionX + Float(pose.headPositionX),
                    positionY: partial.positionY + Float(pose.headPositionY),
                    positionZ: partial.positionZ + Float(pose.headPositionZ),
                    yawDeg: partial.yawDeg + Float(pose.headYawDeg),
                    pitchDeg: partial.pitchDeg + Float(pose.headPitchDeg),
                    rollDeg: partial.rollDeg + Float(pose.headRollDeg)
                )
            }
        )
        return HeadPoseSnapshot(
            positionX: sum.positionX / count,
            positionY: sum.positionY / count,
            positionZ: sum.positionZ / count,
            yawDeg: sum.yawDeg / count,
            pitchDeg: sum.pitchDeg / count,
            rollDeg: sum.rollDeg / count
        )
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let n = sorted.count
        return n.isMultiple(of: 2) ? (sorted[n / 2 - 1] + sorted[n / 2]) / 2 : sorted[n / 2]
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let scale = pow(10.0, Double(places))
        return (self * scale).rounded() / scale
    }
}
