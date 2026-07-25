import SwiftUI
import SceneKit
import CoreMotion

/// Forge's own tilt-responsive 3D badge (APP_REDESIGN_SPEC.md §11) —
/// deliberately distinct from Apple Fitness's hexagon/circle/banner,
/// metallic-bevel badges:
/// - **Shape**: a rounded-square "tile," extruded from a rounded-rect
///   `UIBezierPath` via `SCNShape` — not Apple's hexagon.
/// - **Material**: PBR `clearCoat` over a low-metalness, semi-transparent
///   colored base — a flatter glass finish matching the app's own Liquid
///   Glass language, not Apple's metallic bevel.
/// - **Interaction** (kept — a general technique, not Apple-exclusive per
///   §11): `CMMotionManager` device-motion attitude drives the key light's
///   position and a slight camera tilt, so tilting the phone moves the
///   badge's highlight/perspective.
///
/// Built as a real `SCNView` wrapped via `UIViewRepresentable`, not SwiftUI's
/// higher-level `SceneView` — `SceneView` doesn't expose a way to make its
/// backing layer transparent, and a badge floating on a translucent
/// `.regularMaterial` card needs a transparent backing to actually look like
/// a floating glass tile rather than a solid square. Also not RealityKit's
/// `RealityView`: that API is oriented toward AR/volumetric scenes, whereas
/// SCNView is a plain, long-established "render this small object" view —
/// the simpler, more directly-applicable choice for a 2D-embedded badge.
///
/// Simulator hardware has no motion sensors
/// (`CMMotionManager.isDeviceMotionAvailable` is false there), so this falls
/// back to a fixed default lighting angle rather than crashing — this pass
/// could only be build/launch-verified in Simulator; the actual tilt feel
/// needs on-device confirmation.
struct Badge3DView: UIViewRepresentable {
    let color: Color

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .clear
        scnView.isOpaque = false
        scnView.antialiasingMode = .multisampling4X
        scnView.scene = context.coordinator.scene
        scnView.pointOfView = context.coordinator.cameraNode
        scnView.autoenablesDefaultLighting = false
        context.coordinator.startMotionUpdates()
        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.updateColor(color)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(color: color)
    }

    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) {
        coordinator.stopMotionUpdates()
    }

    final class Coordinator {
        let scene: SCNScene
        let cameraNode: SCNNode
        let lightNode: SCNNode
        private let badgeMaterial: SCNMaterial
        private let motionManager = CMMotionManager()

        init(color: Color) {
            let scene = SCNScene()
            scene.background.contents = UIColor.clear

            let path = UIBezierPath(roundedRect: CGRect(x: -1, y: -1, width: 2, height: 2), cornerRadius: 0.55)
            let shape = SCNShape(path: path, extrusionDepth: 0.35)
            let material = SCNMaterial()
            material.lightingModel = .physicallyBased
            material.diffuse.contents = UIColor(color)
            material.metalness.contents = 0.05
            material.roughness.contents = 0.3
            material.clearCoat.contents = 1.0
            material.clearCoatRoughness.contents = 0.12
            material.transparency = 0.72
            shape.materials = [material]
            badgeMaterial = material

            let badgeNode = SCNNode(geometry: shape)
            scene.rootNode.addChildNode(badgeNode)

            let camera = SCNNode()
            camera.camera = SCNCamera()
            camera.position = SCNVector3(0, 0, 3.2)
            scene.rootNode.addChildNode(camera)
            cameraNode = camera

            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 300
            scene.rootNode.addChildNode(ambient)

            let light = SCNNode()
            light.light = SCNLight()
            light.light?.type = .omni
            light.light?.intensity = 1000
            light.position = SCNVector3(1, 1.5, 2.5)
            scene.rootNode.addChildNode(light)
            lightNode = light

            self.scene = scene
        }

        func updateColor(_ color: Color) {
            badgeMaterial.diffuse.contents = UIColor(color)
        }

        func startMotionUpdates() {
            guard motionManager.isDeviceMotionAvailable else { return }
            motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let self, let motion else { return }
                let roll = motion.attitude.roll
                let pitch = motion.attitude.pitch
                self.lightNode.position = SCNVector3(Float(roll) * 2.5, 1.5 + Float(pitch) * 2.0, 2.5)
                self.cameraNode.eulerAngles = SCNVector3(Float(pitch) * 0.15, Float(roll) * 0.15, 0)
            }
        }

        func stopMotionUpdates() {
            motionManager.stopDeviceMotionUpdates()
        }
    }
}

#Preview {
    Badge3DView(color: .green)
        .frame(width: 140, height: 140)
        .padding()
}
