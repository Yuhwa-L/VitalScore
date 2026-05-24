import SwiftUI
import UniformTypeIdentifiers

struct AdvancedEyeOCTBridgeView: View {
    @EnvironmentObject private var storage: LocalStorageManager
    @State private var importedSnapshot: OCTMetricSnapshot?
    @State private var importError: String?
    @State private var showImporter = false
    @State private var usingDemoSnapshot = true

    private var latestEyeRecord: DailyHealthRecord? {
        storage.loadAllRecords()
            .filter { $0.eyeFocusScore != nil }
            .sorted { $0.date < $1.date }
            .last
    }

    private var activeSnapshot: OCTMetricSnapshot? {
        importedSnapshot ?? (usingDemoSnapshot ? .demo : nil)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                researchStatus
                signalGrid
                workflowPanel
                importPanel
                referencePanel
            }
            .padding()
        }
        .navigationTitle("Advanced Eye")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json, .commaSeparatedText, .plainText],
            allowsMultipleSelection: false,
            onCompletion: handleImport
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("OCT Research Bridge", systemImage: "eye.trianglebadge.exclamationmark")
                .font(.title3.weight(.semibold))
            Text("Research demo for linking app eye-tracking behavior with OCT/OCTA retinal structure and functional response metrics.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Not a medical device, diagnosis, or clinical screening result.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var researchStatus: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Fusion Readiness", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline)
                Spacer()
                Text(fusionReadinessLabel)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(fusionReadinessColor.opacity(0.14))
                    .foregroundStyle(fusionReadinessColor)
                    .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 8) {
                readinessRow(
                    title: "Eye tracking",
                    value: latestEyeRecord == nil ? "No recent run" : "Latest run linked",
                    systemImage: "eye",
                    tint: .indigo
                )
                readinessRow(
                    title: "OCT structure",
                    value: activeSnapshot?.hasStructuralMetrics == true ? "Metrics present" : "Waiting for metrics",
                    systemImage: "square.stack.3d.up",
                    tint: .blue
                )
                readinessRow(
                    title: "fOCTA response",
                    value: activeSnapshot?.hasFunctionalMetrics == true ? "rNVC fields present" : "Optional fields missing",
                    systemImage: "waveform.path.ecg.rectangle",
                    tint: .teal
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    private var signalGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            OCTSignalTile(
                title: "Eye Score",
                value: format(latestEyeRecord?.eyeFocusScore, digits: 0) ?? "--",
                unit: "",
                detail: "behavior",
                systemImage: "eye.circle",
                tint: .indigo
            )
            OCTSignalTile(
                title: "Gaze Loss",
                value: format(latestEyeRecord?.gazeTrackingLossPct, digits: 1) ?? "--",
                unit: "%",
                detail: "quality",
                systemImage: "viewfinder.circle",
                tint: .purple
            )
            OCTSignalTile(
                title: "RNFL",
                value: format(activeSnapshot?.retinalNerveFiberLayerMicrons, digits: 1) ?? "--",
                unit: "um",
                detail: "structure",
                systemImage: "square.stack.3d.down.right",
                tint: .blue
            )
            OCTSignalTile(
                title: "Vessel Density",
                value: format(activeSnapshot?.vesselDensityPercent, digits: 1) ?? "--",
                unit: "%",
                detail: "OCTA",
                systemImage: "point.3.filled.connected.trianglepath.dotted",
                tint: .cyan
            )
            OCTSignalTile(
                title: "rNVC Peak",
                value: format(activeSnapshot?.capillaryRNVCResponsePercent, digits: 1) ?? "--",
                unit: "%",
                detail: "flicker response",
                systemImage: "waveform.path",
                tint: .teal
            )
            OCTSignalTile(
                title: "Time to Peak",
                value: format(activeSnapshot?.rnvcTimeToPeakSeconds, digits: 1) ?? "--",
                unit: "s",
                detail: "response delay",
                systemImage: "timer",
                tint: .orange
            )
        }
    }

    private var workflowPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Research Signal Stack", systemImage: "list.bullet.rectangle")
                .font(.headline)

            ForEach(OCTResearchStep.allCases) { step in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: step.systemImage)
                        .frame(width: 24)
                        .foregroundStyle(step.tint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.title)
                            .font(.subheadline.weight(.semibold))
                        Text(step.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    private var importPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("OCT Data Connector", systemImage: "doc.badge.plus")
                    .font(.headline)
                Spacer()
                if activeSnapshot != nil {
                    Text(importedSnapshot == nil ? "Demo" : "Imported")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(importedSnapshot == nil ? .orange : .green)
                }
            }

            if let snapshot = activeSnapshot {
                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.sourceFileName ?? "Example OCT/OCTA metric export")
                        .font(.subheadline.weight(.medium))
                    Text(snapshot.importedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let importError {
                Text(importError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 10) {
                Button {
                    showImporter = true
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    importedSnapshot = nil
                    usingDemoSnapshot.toggle()
                    importError = nil
                } label: {
                    Label(usingDemoSnapshot ? "Hide Demo" : "Demo", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Text("Accepted demo fields include RNFL/GCC/macular thickness, OCTA vessel density, capillary rNVC peak response, and time-to-peak.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    private var referencePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Preprint Basis", systemImage: "text.book.closed")
                .font(.headline)
            Text("Liu et al. used functional OCT angiography with flicker light stimulation to measure retinal neurovascular coupling in a premotor Parkinson's mouse model.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("The paper is a preprint and the reported disease-screening claims are not implemented here.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    private var fusionReadinessLabel: String {
        guard latestEyeRecord != nil else { return "Needs eye run" }
        guard let snapshot = activeSnapshot else { return "Needs OCT" }
        if snapshot.hasFunctionalMetrics { return "Research linked" }
        return "Structure linked"
    }

    private var fusionReadinessColor: Color {
        switch fusionReadinessLabel {
        case "Research linked":
            return .green
        case "Structure linked":
            return .blue
        default:
            return .orange
        }
    }

    private func readinessRow(title: String, value: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 22)
                .foregroundStyle(tint)
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let canAccess = url.startAccessingSecurityScopedResource()
            defer {
                if canAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            importedSnapshot = try OCTImportParser.parse(url: url)
            usingDemoSnapshot = false
            importError = nil
        } catch {
            importError = error.localizedDescription
        }
    }

    private func format(_ value: Double?, digits: Int) -> String? {
        guard let value else { return nil }
        return String(format: "%.\(digits)f", value)
    }
}

private struct OCTSignalTile: View {
    let title: String
    let value: String
    let unit: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Spacer()
            }
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 122, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}

private struct OCTMetricSnapshot: Identifiable, Equatable {
    let id = UUID()
    let importedAt: Date
    let sourceFileName: String?
    let retinalNerveFiberLayerMicrons: Double?
    let ganglionCellComplexMicrons: Double?
    let macularThicknessMicrons: Double?
    let vesselDensityPercent: Double?
    let capillaryRNVCResponsePercent: Double?
    let rnvcTimeToPeakSeconds: Double?
    let signalStrength: Double?

    var hasStructuralMetrics: Bool {
        retinalNerveFiberLayerMicrons != nil
            || ganglionCellComplexMicrons != nil
            || macularThicknessMicrons != nil
    }

    var hasFunctionalMetrics: Bool {
        vesselDensityPercent != nil
            || capillaryRNVCResponsePercent != nil
            || rnvcTimeToPeakSeconds != nil
    }

    static let demo = OCTMetricSnapshot(
        importedAt: Date(),
        sourceFileName: "demo_focta_rnvc_metrics.json",
        retinalNerveFiberLayerMicrons: 94.2,
        ganglionCellComplexMicrons: 82.6,
        macularThicknessMicrons: 267.4,
        vesselDensityPercent: 47.8,
        capillaryRNVCResponsePercent: 18.5,
        rnvcTimeToPeakSeconds: 12.0,
        signalStrength: 8.7
    )
}

private enum OCTResearchStep: CaseIterable, Identifiable {
    case behavior
    case structure
    case function
    case review

    var id: String { title }

    var title: String {
        switch self {
        case .behavior:
            return "Eye-tracking behavior"
        case .structure:
            return "OCT structure"
        case .function:
            return "fOCTA/OCTA response"
        case .review:
            return "Clinician/research review"
        }
    }

    var detail: String {
        switch self {
        case .behavior:
            return "Reaction timing, gaze stability, fixation behavior, blink rate, and tracking quality."
        case .structure:
            return "Retinal layer thickness and macular structure from OCT export files."
        case .function:
            return "Capillary vessel-density and retinal neurovascular coupling response fields from OCTA/fOCTA."
        case .review:
            return "Research flags can support follow-up conversations, never automated diagnosis."
        }
    }

    var systemImage: String {
        switch self {
        case .behavior:
            return "eye"
        case .structure:
            return "square.stack.3d.up"
        case .function:
            return "waveform.path.ecg.rectangle"
        case .review:
            return "person.text.rectangle"
        }
    }

    var tint: Color {
        switch self {
        case .behavior:
            return .indigo
        case .structure:
            return .blue
        case .function:
            return .teal
        case .review:
            return .orange
        }
    }
}

private enum OCTImportParser {
    static func parse(url: URL) throws -> OCTMetricSnapshot {
        let data = try Data(contentsOf: url)
        let values: [String: Any]
        if url.pathExtension.lowercased() == "json" {
            values = try parseJSON(data)
        } else {
            values = parseDelimitedText(String(decoding: data, as: UTF8.self))
        }

        return OCTMetricSnapshot(
            importedAt: Date(),
            sourceFileName: url.lastPathComponent,
            retinalNerveFiberLayerMicrons: number(
                in: values,
                keys: ["rnfl", "rnfl_um", "rnflThicknessMicrons", "retinalNerveFiberLayerMicrons"]
            ),
            ganglionCellComplexMicrons: number(
                in: values,
                keys: ["gcc", "gcc_um", "ganglionCellComplexMicrons"]
            ),
            macularThicknessMicrons: number(
                in: values,
                keys: ["macularThickness", "macularThicknessMicrons", "centralMacularThicknessMicrons"]
            ),
            vesselDensityPercent: number(
                in: values,
                keys: ["vesselDensity", "vesselDensityPercent", "octaVesselDensityPercent"]
            ),
            capillaryRNVCResponsePercent: number(
                in: values,
                keys: ["rnvcPeak", "rnvcPeakPercent", "capillaryRNVCResponsePercent", "deltaRBFPercent"]
            ),
            rnvcTimeToPeakSeconds: number(
                in: values,
                keys: ["rnvcTimeToPeak", "rnvcTimeToPeakSeconds", "timeToPeakSeconds"]
            ),
            signalStrength: number(
                in: values,
                keys: ["signalStrength", "octSignalStrength", "quality"]
            )
        )
    }

    private static func parseJSON(_ data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        return flatten(object)
    }

    private static func parseDelimitedText(_ text: String) -> [String: Any] {
        let rows = text
            .split(whereSeparator: \.isNewline)
            .map { $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }
        guard let headers = rows.first, let values = rows.dropFirst().first else { return [:] }

        var result: [String: Any] = [:]
        for (index, header) in headers.enumerated() where index < values.count {
            result[header] = values[index]
        }
        return result
    }

    private static func flatten(_ object: Any) -> [String: Any] {
        var result: [String: Any] = [:]
        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary {
                result[key] = value
                flatten(value).forEach { nestedKey, nestedValue in
                    result[nestedKey] = nestedValue
                }
            }
        } else if let array = object as? [Any] {
            array.forEach {
                flatten($0).forEach { key, value in
                    result[key] = value
                }
            }
        }
        return result
    }

    private static func number(in values: [String: Any], keys: [String]) -> Double? {
        let normalizedKeys = Set(keys.map(normalize))
        for (key, value) in values where normalizedKeys.contains(normalize(key)) {
            if let number = value as? NSNumber {
                return number.doubleValue
            }
            if let text = value as? String {
                return Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return nil
    }

    private static func normalize(_ key: String) -> String {
        key.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
