import SwiftUI

struct EyeFocusTestView: View {
    @StateObject private var manager = EyeFocusTestManager()
    @Environment(\.dismiss) private var dismiss
    let onFinished: (EyeFocusTestResult) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                content(in: geo.size)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Cancel") {
                    manager.cancel()
                    dismiss()
                }
                .foregroundColor(.white)
            }
        }
        .onChange(of: manager.phase) { _, newPhase in
            if case .finished(let result) = newPhase {
                onFinished(result)
            }
        }
    }

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        switch manager.phase {
        case .idle:
            VStack(spacing: 20) {
                Text("Eye-Focus Test")
                    .font(.title)
                    .foregroundColor(.white)
                Text("Follow the dot with your eyes. Tap only when the dot turns red. The test runs for 30 seconds.")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button {
                    manager.start()
                } label: {
                    Text("Start")
                        .font(.headline)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .foregroundColor(.black)
                        .cornerRadius(12)
                }
            }
        case .countdown(let n):
            Text("\(n)")
                .font(.system(size: 96, weight: .bold))
                .foregroundColor(.white)
        case .running:
            ZStack {
                Color.black.ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { manager.recordTap() }
                Circle()
                    .fill(manager.dotIsTarget ? Color.red : Color.white)
                    .frame(width: 44, height: 44)
                    .position(
                        x: manager.dotPosition.x * size.width,
                        y: manager.dotPosition.y * size.height
                    )
                    .allowsHitTesting(false)
            }
        case .finished(let result):
            VStack(spacing: 16) {
                Text("Eye-Focus Score")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.8))
                Text("\(Int(result.eyeFocusScore))")
                    .font(.system(size: 72, weight: .bold))
                    .foregroundColor(.white)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Average reaction: \(Int(result.averageReactionMs)) ms")
                    Text("Variability: \(Int(result.reactionStdDevMs)) ms")
                    Text("Missed targets: \(result.missedTargets)")
                    Text("False taps: \(result.falseTaps)")
                }
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            }
        }
    }
}
