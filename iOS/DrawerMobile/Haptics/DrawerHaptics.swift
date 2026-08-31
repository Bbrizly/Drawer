import SwiftUI
import UIKit

extension Notification.Name {
    static let drawerActionFeedback = Notification.Name("com.bbrizly.drawer.action-feedback")
}

struct DrawerActionFeedbackPayload: Identifiable, Equatable, Sendable {
    let id = UUID()
    let message: String
    let systemImage: String
}

/// One small, app-wide acknowledgement channel for state-changing actions.
/// Haptics remain the tactile grammar; this gives the same mutation a visible
/// and VoiceOver-readable confirmation without turning every control into a
/// toast factory.
@MainActor
enum DrawerActionFeedbackCenter {
    static func success(_ message: String, systemImage: String = "checkmark.circle.fill") {
        post(message, systemImage: systemImage)
    }

    static func notice(_ message: String, systemImage: String) {
        post(message, systemImage: systemImage)
    }

    static func announce(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private static func post(_ message: String, systemImage: String) {
        let payload = DrawerActionFeedbackPayload(message: message, systemImage: systemImage)
        NotificationCenter.default.post(name: .drawerActionFeedback, object: payload)
        announce(message)
    }
}

@MainActor
final class DrawerHaptics {
    static let shared = DrawerHaptics()

    private let selection = UISelectionFeedbackGenerator()
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let notification = UINotificationFeedbackGenerator()

    private init() { prepareCommon() }

    func prepareForSwipe() {
        selection.prepare()
        rigid.prepare()
    }

    func swipeThreshold() {
        selection.selectionChanged()
        selection.prepare()
    }

    func taskCompleted() {
        notification.notificationOccurred(.success)
        notification.prepare()
    }

    func taskReopened() {
        light.impactOccurred(intensity: 0.72)
        light.prepare()
    }

    func taskAdded() {
        soft.impactOccurred(intensity: 0.82)
        soft.prepare()
    }

    /// Quiet acknowledgement for a persisted text edit; deliberately softer
    /// than creating a task so note editing never feels like a new object.
    func saved() {
        light.impactOccurred(intensity: 0.52)
        light.prepare()
    }

    func progressChanged() {
        selection.selectionChanged()
        selection.prepare()
    }

    func recurrenceChanged() {
        selection.selectionChanged()
        selection.prepare()
    }

    func skipped() {
        light.impactOccurred(intensity: 0.62)
        light.prepare()
    }

    func moved() {
        selection.selectionChanged()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) { [weak self] in
            self?.light.impactOccurred(intensity: 0.7)
            self?.light.prepare()
        }
    }

    func destructiveArmed() {
        rigid.impactOccurred(intensity: 0.82)
        rigid.prepare()
    }

    func deleted() {
        notification.notificationOccurred(.warning)
        notification.prepare()
    }

    func undo() {
        light.impactOccurred(intensity: 0.78)
        light.prepare()
    }

    func focusStarted() {
        medium.impactOccurred(intensity: 0.78)
        medium.prepare()
    }

    func focusPaused() {
        selection.selectionChanged()
        selection.prepare()
    }

    func focusFinished() {
        notification.notificationOccurred(.success)
        notification.prepare()
    }

    func focusDismissed() {
        light.impactOccurred(intensity: 0.5)
        light.prepare()
    }

    /// Group/session completion is intentionally rare, so this can have a
    /// slightly firmer closure than an ordinary selection without becoming
    /// celebratory or noisy.
    func groupFinished() {
        medium.impactOccurred(intensity: 0.88)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.055) { [weak self] in
            self?.notification.notificationOccurred(.success)
            self?.notification.prepare()
        }
    }

    func error() {
        notification.notificationOccurred(.error)
        notification.prepare()
    }

    private func prepareCommon() {
        selection.prepare()
        light.prepare()
        medium.prepare()
        rigid.prepare()
        soft.prepare()
        notification.prepare()
    }
}

/// Press treatment should read as physical depth, not as a disabled/faded
/// control. The scale change carries most of the tactile illusion; opacity only
/// softens very slightly so text/icons remain crisp through rapid repeated taps.
struct TactileButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var pressedScale: CGFloat = 0.975
    var pressedOpacity: Double = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.15, dampingFraction: 0.78),
                value: configuration.isPressed
            )
    }
}
