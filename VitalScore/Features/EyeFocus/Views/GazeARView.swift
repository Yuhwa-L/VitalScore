import SwiftUI
import ARKit
import SceneKit

struct GazeARView: UIViewRepresentable {
    let service: GazeTrackingService

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.scene = SCNScene()
        view.backgroundColor = .black
        view.isOpaque = true
        view.rendersContinuously = true
        view.automaticallyUpdatesLighting = false
        view.allowsCameraControl = false
        view.showsStatistics = false

        if let cameraNode = view.pointOfView?.camera {
            cameraNode.wantsHDR = false
        }

        if ARFaceTrackingConfiguration.isSupported {
            let config = ARFaceTrackingConfiguration()
            config.isLightEstimationEnabled = false
            config.maximumNumberOfTrackedFaces = 1
            if ARFaceTrackingConfiguration.supportsWorldTracking {
                config.isWorldTrackingEnabled = true
            }
            view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
            service.attach(session: view.session)
        }
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: ()) {
        uiView.session.pause()
    }
}
