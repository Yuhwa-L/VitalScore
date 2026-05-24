import SwiftUI

enum FaceGuideStatus {
    case noFace
    case tooClose
    case tooFar
    case offCenter
    case good

    var color: Color {
        switch self {
        case .good: return .green
        case .offCenter, .tooClose, .tooFar: return .yellow
        case .noFace: return .red
        }
    }

    var label: String {
        switch self {
        case .good: return "Face position: good — hold still"
        case .offCenter: return "Center your face in the oval"
        case .tooClose: return "Move phone away — too close"
        case .tooFar: return "Move phone closer"
        case .noFace: return "Face not detected — look at the camera"
        }
    }
}

struct FaceGuideOverlay: View {
    let isTracked: Bool
    let faceCenterInFrame: CGPoint
    let faceDistanceM: Float
    let containerSize: CGSize
    var compact: Bool = false

    static let goodDistanceRange: ClosedRange<Float> = 0.22...0.40
    static let okDistanceRange: ClosedRange<Float> = 0.18...0.50
    static let goodCenterTolerance: CGFloat = 0.20

    var ovalSize: CGSize {
        if compact {
            return CGSize(width: 60, height: 80)
        }
        let w = containerSize.width * 0.72
        let h = w * 1.35
        return CGSize(width: w, height: h)
    }

    var status: FaceGuideStatus {
        guard isTracked else { return .noFace }
        if faceDistanceM < Self.okDistanceRange.lowerBound { return .tooClose }
        if faceDistanceM > Self.okDistanceRange.upperBound { return .tooFar }
        let dx = abs(faceCenterInFrame.x - 0.5)
        let dy = abs(faceCenterInFrame.y - 0.5)
        if dx > Self.goodCenterTolerance || dy > Self.goodCenterTolerance { return .offCenter }
        if !Self.goodDistanceRange.contains(faceDistanceM) { return .tooFar }
        return .good
    }

    private var ovalCenter: CGPoint {
        if compact {
            return CGPoint(x: containerSize.width / 2, y: 75)
        }
        return CGPoint(x: containerSize.width / 2, y: containerSize.height * 0.45)
    }

    private var faceDotPosition: CGPoint {
        let dx = (faceCenterInFrame.x - 0.5) * ovalSize.width * 0.6
        let dy = (faceCenterInFrame.y - 0.5) * ovalSize.height * 0.6
        return CGPoint(x: ovalCenter.x + dx, y: ovalCenter.y + dy)
    }

    var body: some View {
        ZStack {
            Ellipse()
                .stroke(status.color.opacity(compact ? 0.85 : 0.9),
                        style: StrokeStyle(lineWidth: compact ? 2 : 4,
                                           dash: compact ? [4, 4] : [10, 8]))
                .frame(width: ovalSize.width, height: ovalSize.height)
                .position(ovalCenter)

            if isTracked {
                Circle()
                    .fill(status.color)
                    .frame(width: compact ? 8 : 14, height: compact ? 8 : 14)
                    .position(faceDotPosition)
            }

            if !compact {
                VStack(spacing: 4) {
                    Text(status.label)
                        .font(.subheadline).bold()
                        .foregroundColor(.white)
                    if isTracked {
                        Text("Distance: \(String(format: "%.2f", faceDistanceM)) m  •  aim for 0.25–0.35 m")
                            .font(.caption.monospaced())
                            .foregroundColor(.white.opacity(0.75))
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.black.opacity(0.55))
                .cornerRadius(10)
                .position(x: containerSize.width / 2, y: 60)
            }
        }
    }
}
