#if os(iOS)
import CoreMotion
import GameController
import SwiftUI

/// Watches connected controllers only while a reviewer is active.
struct ReviewerController: ViewModifier {
    let onInput: @MainActor (ReviewerInput) -> Void
    @State private var profiles: [ObjectIdentifier: [GCControllerButtonInput]] = [:]

    func body(content: Content) -> some View {
        content
            .onAppear { GCController.controllers().forEach(attach) }
            .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidConnect)) { event in
                if let controller = event.object as? GCController { attach(controller) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)) { event in
                if let controller = event.object as? GCController { detach(ObjectIdentifier(controller)) }
            }
            .onDisappear {
                for buttons in profiles.values {
                    buttons.forEach { $0.pressedChangedHandler = nil }
                }
                profiles.removeAll()
            }
    }

    private func attach(_ controller: GCController) {
        let identity = ObjectIdentifier(controller)
        guard profiles[identity] == nil else { return }
        var buttons: [(String, GCControllerButtonInput?)] = []
        if let pad = controller.extendedGamepad {
            buttons = [
                ("buttonA", pad.buttonA), ("buttonB", pad.buttonB), ("buttonX", pad.buttonX), ("buttonY", pad.buttonY),
                ("buttonMenu", pad.buttonMenu), ("buttonOptions", pad.buttonOptions), ("buttonHome", pad.buttonHome),
                ("leftShoulder", pad.leftShoulder), ("rightShoulder", pad.rightShoulder),
                ("leftTrigger", pad.leftTrigger), ("rightTrigger", pad.rightTrigger),
                ("leftStick", pad.leftThumbstickButton), ("rightStick", pad.rightThumbstickButton),
            ] + Self.directions(pad.dpad, prefix: "dpad")
        } else if let pad = controller.microGamepad {
            buttons = [
                ("buttonA", pad.buttonA), ("buttonX", pad.buttonX), ("buttonMenu", pad.buttonMenu),
            ] + Self.directions(pad.dpad, prefix: "dpad")
        }
        profiles[identity] = buttons.compactMap { name, button in
            button?.pressedChangedHandler = { _, _, pressed in
                guard pressed else { return }
                Task { @MainActor in onInput(.controller(name)) }
            }
            return button
        }
    }

    private func detach(_ identity: ObjectIdentifier) {
        profiles.removeValue(forKey: identity)?.forEach { $0.pressedChangedHandler = nil }
    }

    private static func directions(_ pad: GCControllerDirectionPad, prefix: String) -> [(String, GCControllerButtonInput?)] {
        [("\(prefix)Up", pad.up), ("\(prefix)Down", pad.down), ("\(prefix)Left", pad.left), ("\(prefix)Right", pad.right)]
    }
}

/// Samples motion only when Shake has a binding on the current side.
struct ReviewerShake: ViewModifier {
    let enabled: Bool
    let onShake: @MainActor () -> Void
    @State private var motion = CMMotionManager()
    @State private var lastShake = ContinuousClock.now - .seconds(2)

    func body(content: Content) -> some View {
        content
            .onChange(of: enabled, initial: true) { _, enabled in
                motion.stopDeviceMotionUpdates()
                guard enabled, motion.isDeviceMotionAvailable else { return }
                motion.deviceMotionUpdateInterval = 1 / 25
                motion.startDeviceMotionUpdates(to: .main) { data, _ in
                    guard let a = data?.userAcceleration, a.x * a.x + a.y * a.y + a.z * a.z > 4 else { return }
                    MainActor.assumeIsolated {
                        let now = ContinuousClock.now
                        guard now - lastShake >= .seconds(1) else { return }
                        lastShake = now
                        onShake()
                    }
                }
            }
            .onDisappear { motion.stopDeviceMotionUpdates() }
    }
}
#endif
