import SwiftUI
import UIKit

struct EyeFocusTestView: View {
    @StateObject private var manager = EyeFocusTestManager()
    @State private var didDeliverResult = false
    @Environment(\.dismiss) private var dismiss
    let experimentTag: String
    let onFinished: (EyeFocusTestResult) -> Void

    init(
        experimentTag: String = ExperimentTagValue.untagged,
        onFinished: @escaping (EyeFocusTestResult) -> Void
    ) {
        self.experimentTag = ExperimentTagValue.normalized(experimentTag)
        self.onFinished = onFinished
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if showResultBackground {
                    Color.white.ignoresSafeArea()
                } else {
                    Color.black.ignoresSafeArea()

                    if case .arkit = manager.gazeBackend, let arkit = manager.arkitService {
                        GazeARView(service: arkit)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                        Color.black.opacity(arkitDimming).ignoresSafeArea()
                    }

                    if case .vision = manager.gazeBackend, let vision = manager.visionService {
                        CameraPreviewView(session: vision.session)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                        Color.black.opacity(manager.phase == .idle ? 0.4 : 0.55).ignoresSafeArea()
                    }
                }

                content(in: geo.size)
            }
            .onAppear {
                manager.setExperimentTag(experimentTag)
                manager.setScreenSize(geo.size)
            }
            .onChange(of: experimentTag) { _, newTag in
                manager.setExperimentTag(newTag)
            }
            .onChange(of: geo.size) { _, newSize in
                manager.setScreenSize(newSize)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if case .finished(let result) = manager.phase {
                    Button("Done") {
                        complete(result)
                    }
                    .foregroundColor(.black)
                } else {
                    Button("Cancel") {
                        manager.cancel()
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        switch manager.phase {
        case .idle:
            idleView
        case .ready:
            readyView(size: size)
        case .calibrating(let index):
            calibratingView(size: size, pointIndex: index)
        case .countdown(let n):
            ZStack {
                Text("\(n)")
                    .font(.system(size: 96, weight: .bold))
                    .foregroundColor(.white)
                compactFaceGuide(size: size)
                if case .vision = manager.gazeBackend, let vision = manager.visionService {
                    VStack { Spacer(); visionStatusBadge(vision: vision).padding(.bottom, 30) }
                }
            }
        case .running:
            runningView(size: size)
        case .processing:
            processingView
        case .finished(let result):
            resultView(result)
        }
    }

    @ViewBuilder
    private var processingView: some View {
        VStack(spacing: 18) {
            ProgressView()
                .scaleEffect(1.8)
                .tint(.black)
            Text("Processing your results…")
                .font(.headline)
                .foregroundColor(.black)
            Text("Aggregating gaze samples, saving log, and preparing summary")
                .font(.caption)
                .foregroundColor(.black.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(28)
    }

    @ViewBuilder
    private func readyView(size: CGSize) -> some View {
        ZStack {
            if case .arkit = manager.gazeBackend, let arkit = manager.arkitService {
                FaceGuideOverlay(
                    isTracked: arkit.isTracking,
                    faceCenterInFrame: arkit.faceCenterInFrame,
                    faceDistanceM: arkit.faceDistanceM,
                    containerSize: size
                )
                .allowsHitTesting(false)
            }
            if case .vision = manager.gazeBackend, let vision = manager.visionService {
                VStack {
                    visionStatusBadge(vision: vision)
                        .padding(.top, 28)
                    Spacer()
                }
            }

            VStack(spacing: 14) {
                Spacer()
                Text("Position your face in the oval, then tap to begin.")
                    .font(.subheadline).foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center).padding(.horizontal)
                Button {
                    manager.beginCalibration()
                } label: {
                    Text(beginCalibrationLabel)
                        .font(.headline)
                        .padding(.horizontal, 28).padding(.vertical, 14)
                        .background(beginCalibrationEnabled ? Color.white : Color.gray.opacity(0.6))
                        .foregroundColor(.black)
                        .cornerRadius(12)
                }
                .disabled(!beginCalibrationEnabled)
                .padding(.bottom, 50)
            }
        }
    }

    private var beginCalibrationEnabled: Bool {
        switch manager.gazeBackend {
        case .arkit:
            guard let arkit = manager.arkitService else { return false }
            let status = FaceGuideOverlay(
                isTracked: arkit.isTracking,
                faceCenterInFrame: arkit.faceCenterInFrame,
                faceDistanceM: arkit.faceDistanceM,
                containerSize: CGSize(width: 1, height: 1)
            ).status
            return status == .good
        case .vision:
            return manager.visionService?.faceQualityGood == true
        case .none:
            return true
        }
    }

    private var beginCalibrationLabel: String {
        beginCalibrationEnabled
            ? "Begin Calibration"
            : "Hold position…"
    }

    @ViewBuilder
    private func compactFaceGuide(size: CGSize) -> some View {
        if case .arkit = manager.gazeBackend, let arkit = manager.arkitService {
            FaceGuideOverlay(
                isTracked: arkit.isTracking,
                faceCenterInFrame: arkit.faceCenterInFrame,
                faceDistanceM: arkit.faceDistanceM,
                containerSize: size
            )
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func calibratingView(size: CGSize, pointIndex: Int) -> some View {
        ZStack {
            Color.clear.contentShape(Rectangle())

            if case .arkit = manager.gazeBackend, let arkit = manager.arkitService {
                FaceGuideOverlay(
                    isTracked: arkit.isTracking,
                    faceCenterInFrame: arkit.faceCenterInFrame,
                    faceDistanceM: arkit.faceDistanceM,
                    containerSize: size
                )
                .allowsHitTesting(false)
            }

            ZStack {
                Circle()
                    .stroke(Color.cyan.opacity(0.35), lineWidth: 2)
                    .frame(width: 70, height: 70)
                Circle()
                    .trim(from: 0, to: manager.calibrationProgress)
                    .stroke(manager.calibrationIsCollecting ? Color.green : Color.cyan,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 70, height: 70)
                    .rotationEffect(.degrees(-90))
                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)
            }
            .position(x: manager.dotPosition.x * size.width,
                      y: manager.dotPosition.y * size.height)

            VStack(spacing: 4) {
                Text("Calibration  •  Point \(pointIndex + 1) of \(manager.calibrationTargetCount)")
                    .font(.caption).foregroundColor(.white.opacity(0.8))
                Text(calibrationInstruction)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.65))
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.black.opacity(0.55))
            .cornerRadius(8)
            .position(x: size.width / 2, y: size.height - 40)
        }
    }

    private var idleView: some View {
        VStack(spacing: 16) {
            Text("Eye-Focus Test")
                .font(.title)
                .foregroundColor(.white)
            Text(idleInstruction)
                .font(.body)
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Label("Backend: \(manager.gazeBackend.displayName)", systemImage: backendIcon)
                .font(.caption)
                .foregroundColor(manager.gazeAvailable ? .green : .secondary)

            if case .vision = manager.gazeBackend, let vision = manager.visionService {
                permissionRow(vision: vision)
            }

            Button {
                Task { await manager.start() }
            } label: {
                HStack(spacing: 8) {
                    if manager.isPreparing {
                        ProgressView().tint(.black)
                    }
                    Text(manager.isPreparing ? "Requesting camera…" : startButtonLabel)
                        .font(.headline)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(startButtonEnabled ? Color.white : Color.gray)
                .foregroundColor(.black)
                .cornerRadius(12)
            }
            .disabled(!startButtonEnabled || manager.isPreparing)

            if let err = manager.startupError {
                VStack(spacing: 6) {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                    if err.contains("permission") {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("Open Settings")
                                .font(.caption)
                                .underline()
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(.horizontal)
            }

        }
        .padding()
    }

    @ViewBuilder
    private func runningView(size: CGSize) -> some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { manager.recordTap() }

            if manager.gazeAvailable, let gaze = manager.displayGazePoint {
                Circle()
                    .strokeBorder(Color.cyan.opacity(0.85), lineWidth: 3)
                    .frame(width: 36, height: 36)
                    .position(
                        x: max(0, min(size.width, gaze.x * size.width)),
                        y: max(0, min(size.height, gaze.y * size.height))
                    )
                    .allowsHitTesting(false)
            }

            Circle()
                .fill(manager.dotHitFlash ? Color.green : Color.red)
                .frame(width: 44, height: 44)
                .position(x: manager.dotPosition.x * size.width, y: manager.dotPosition.y * size.height)
                .allowsHitTesting(false)

            compactFaceGuide(size: size)

            if case .vision = manager.gazeBackend, let vision = manager.visionService {
                VStack {
                    Spacer()
                    visionStatusBadge(vision: vision)
                        .padding(.bottom, 30)
                }
            }
        }
    }

    @ViewBuilder
    private func resultView(_ result: EyeFocusTestResult) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                resultHero(result)
                keyMetricsGrid(result)
                reportSummary(result)
                signalQualityPanel(result)

                Button {
                    complete(result)
                } label: {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.black)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }

    private func resultHero(_ result: EyeFocusTestResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Eye Movement Report")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.primary)
                    Text(result.completedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                scoreBadge(scoreBand(result.eyeFocusScore))
            }

            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text("\(Int(result.eyeFocusScore.rounded()))")
                    .font(.system(size: 76, weight: .bold))
                    .foregroundColor(scoreColor(result.eyeFocusScore))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Eye-focus score")
                        .font(.headline)
                    Text(heroSubtitle(result))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal)
    }

    private func keyMetricsGrid(_ result: EyeFocusTestResult) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            reportMetricTile(
                title: "Reaction",
                value: "\(Int(result.averageReactionMs.rounded()))",
                unit: "ms avg",
                icon: "bolt.fill",
                tint: .blue,
                footer: "\(Int(result.reactionStdDevMs.rounded())) ms variability"
            )
            reportMetricTile(
                title: "Accuracy",
                value: result.gazeMetrics.map { "\(Int($0.gazeAccuracyPx.rounded()))" } ?? "--",
                unit: "px error",
                icon: "scope",
                tint: .indigo,
                footer: "lower is better"
            )
            reportMetricTile(
                title: "Stability",
                value: result.gazeMetrics.map { "\(Int($0.gazeStabilityPx.rounded()))" } ?? "--",
                unit: "px spread",
                icon: "waveform.path.ecg",
                tint: .teal,
                footer: "steadier gaze signal"
            )
            reportMetricTile(
                title: "Misses",
                value: "\(result.missedTargets + result.falseTaps)",
                unit: "total",
                icon: "hand.tap.fill",
                tint: .orange,
                footer: "\(result.missedTargets) missed, \(result.falseTaps) false"
            )
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func reportSummary(_ result: EyeFocusTestResult) -> some View {
        if let summary = result.aiSummary {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Label("AI Report", systemImage: "sparkles")
                        .font(.headline)
                        .foregroundColor(.indigo)
                    Spacer()
                    if let confidence = summary.confidence {
                        confidenceChip(confidence)
                    }
                }

                Text(shortSummary(summary.overallSummary, maxCharacters: 300))
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(summary.sections) { section in
                    summarySectionRow(section)
                }

                Text("Model: \(summary.model)")
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
            }
            .reportPanel()
            .padding(.horizontal)
        } else if let error = manager.aiSummaryError {
            VStack(alignment: .leading, spacing: 8) {
                Label("AI report unavailable", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundColor(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .reportPanel()
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func signalQualityPanel(_ result: EyeFocusTestResult) -> some View {
        if let g = result.gazeMetrics {
            VStack(alignment: .leading, spacing: 12) {
                Text("Signal Quality")
                    .font(.headline)
                HStack(spacing: 12) {
                    compactMetric("Tracking loss", value: "\(Int(g.trackingLossPct.rounded()))%")
                    compactMetric("Blink rate", value: "\(Int(g.blinkRatePerMin.rounded()))/min")
                    compactMetric("Samples", value: "\(g.sampleCount)")
                }
                HStack(spacing: 12) {
                    compactMetric("Gaze score", value: "\(Int(g.gazeScore.rounded()))")
                    compactMetric("Fixation", value: "\(Int(g.fixationDurationMs.rounded())) ms")
                    compactMetric("Backend", value: manager.gazeBackend.displayName)
                }
            }
            .reportPanel()
            .padding(.horizontal)
        }
    }

    private func reportMetricTile(
        title: String,
        value: String,
        unit: String,
        icon: String,
        tint: Color,
        footer: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundColor(tint)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
            }
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title2.weight(.bold))
                    .foregroundColor(.primary)
                Text(unit)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text(footer)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    private func summarySectionRow(_ section: EyeFocusAISummarySection) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: sectionIcon(section.title))
                .font(.caption.weight(.bold))
                .foregroundColor(.indigo)
                .frame(width: 22, height: 22)
                .background(Color.indigo.opacity(0.1))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(section.title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
                Text(shortSummary(section.summary, maxCharacters: 220))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func compactMetric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func confidenceChip(_ confidence: String) -> some View {
        Text(confidence.capitalized)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(confidenceColor(confidence).opacity(0.14))
            .foregroundColor(confidenceColor(confidence))
            .cornerRadius(8)
    }

    private func scoreBadge(_ band: String) -> some View {
        Text(band)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(scoreBandColor(band).opacity(0.14))
            .foregroundColor(scoreBandColor(band))
            .cornerRadius(8)
    }

    private func complete(_ result: EyeFocusTestResult) {
        guard !didDeliverResult else { return }
        didDeliverResult = true
        onFinished(result)
    }

    private func shortSummary(_ text: String, maxCharacters: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ")
            .joined(separator: " ")

        guard normalized.count > maxCharacters else { return normalized }
        let end = normalized.index(normalized.startIndex, offsetBy: maxCharacters)
        return String(normalized[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private func heroSubtitle(_ result: EyeFocusTestResult) -> String {
        if let summary = result.aiSummary {
            return shortSummary(summary.overallSummary, maxCharacters: 92)
        }
        if result.gazeMetrics == nil {
            return "Reaction timing was captured. Gaze details were not available for this run."
        }
        return "Reaction timing and gaze tracking were combined into this wellness score."
    }

    private func scoreBand(_ score: Double) -> String {
        if score >= 80 { return "Strong" }
        if score >= 60 { return "Steady" }
        return "Needs signal"
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 80 { return .green }
        if score >= 60 { return .primary }
        return .orange
    }

    private func scoreBandColor(_ band: String) -> Color {
        switch band {
        case "Strong": return .green
        case "Steady": return .blue
        default: return .orange
        }
    }

    private func confidenceColor(_ confidence: String) -> Color {
        switch confidence.lowercased() {
        case "high": return .green
        case "medium": return .blue
        default: return .orange
        }
    }

    private func sectionIcon(_ title: String) -> String {
        let normalized = title.lowercased()
        if normalized.contains("performance") || normalized.contains("reaction") {
            return "bolt.fill"
        }
        if normalized.contains("gaze") || normalized.contains("control") {
            return "scope"
        }
        if normalized.contains("quality") || normalized.contains("signal") {
            return "checkmark.seal.fill"
        }
        if normalized.contains("changed") {
            return "chart.line.uptrend.xyaxis"
        }
        if normalized.contains("tip") || normalized.contains("next") {
            return "lightbulb.fill"
        }
        return "circle.fill"
    }

    private var startButtonLabel: String {
        guard case .vision = manager.gazeBackend, let vision = manager.visionService else {
            return "Start"
        }
        switch vision.permissionState {
        case .granted, .unknown: return "Start"
        case .denied: return "Camera denied — open Settings"
        case .restricted: return "Camera restricted"
        }
    }

    private var startButtonEnabled: Bool {
        guard case .vision = manager.gazeBackend, let vision = manager.visionService else {
            return true
        }
        switch vision.permissionState {
        case .denied, .restricted: return false
        default: return true
        }
    }

    @ViewBuilder
    private func permissionRow(vision: VisionGazeTrackingService) -> some View {
        HStack(spacing: 8) {
            switch vision.permissionState {
            case .granted:
                Label("Camera permission granted", systemImage: "checkmark.seal.fill")
                    .foregroundColor(.green)
            case .denied:
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Open Settings to allow Camera", systemImage: "gear")
                        .foregroundColor(.red)
                }
            case .restricted:
                Label("Camera restricted", systemImage: "lock.fill")
                    .foregroundColor(.orange)
            case .unknown:
                Label("Tap Start to grant Camera access", systemImage: "questionmark.circle")
                    .foregroundColor(.yellow)
            }
        }
        .font(.caption)
    }

    @ViewBuilder
    private func visionStatusBadge(vision: VisionGazeTrackingService) -> some View {
        VStack(spacing: 2) {
            Text("frames \(vision.framesReceived) · faces \(vision.facesDetected) · face \(vision.faceQualityGood ? "ok" : "adjust") · tracking \(vision.isTracking ? "yes" : "no")")
                .font(.caption2.monospaced())
                .foregroundColor(.white)
            if let err = vision.lastError {
                Text(err)
                    .font(.caption2.monospaced())
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.black.opacity(0.55))
        .cornerRadius(8)
    }

    private var idleInstruction: String {
        switch manager.gazeBackend {
        case .arkit:
            return "Three steps: (1) position your face in the oval, (2) calibration — look at 9 dots while keeping the phone still, (3) the 30-second test — follow the dot with your eyes and tap when it turns red."
        case .vision:
            return "Three steps: (1) position your face, (2) calibration — look at 9 dots, (3) the 30-second test — follow the dot with your eyes and tap when it turns red. Keep your head fairly still throughout."
        case .none:
            return "Follow the dot with your eyes. Tap only when the dot turns red. The test runs for 30 seconds."
        }
    }

    private var calibrationInstruction: String {
        switch manager.gazeBackend {
        case .arkit:
            return manager.calibrationIsCollecting
                ? "Keep eyes on dot. Keep phone still."
                : "Hold gaze on dot."
        case .vision:
            return "Keep eyes on dot and phone still."
        case .none:
            return ""
        }
    }

    private var backendIcon: String {
        switch manager.gazeBackend {
        case .arkit: return "eye.trianglebadge.exclamationmark"
        case .vision: return "camera.viewfinder"
        case .none: return "eye.slash"
        }
    }

    private var showResultBackground: Bool {
        switch manager.phase {
        case .processing, .finished: return true
        default: return false
        }
    }

    private var arkitDimming: Double {
        switch manager.phase {
        case .ready, .calibrating: return 0.25
        case .idle: return 0.45
        case .countdown, .running: return 0.45
        case .processing, .finished: return 0.7
        }
    }
}

private extension View {
    func reportPanel() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
    }
}
