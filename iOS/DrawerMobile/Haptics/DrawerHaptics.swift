import SwiftUI
import UIKit

@MainActor
final class DrawerHaptics {
    static let shared = DrawerHaptics()

    private let selection = UISelectionFeedbackGenerator()
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let notification = UINotificationFeedbackGenerator()

    private init() {
        prepareCommon()
    }

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

    func progressChanged() {
        selection.selectionChanged()
        selection.prepare()
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

struct TactileButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var pressedScale: CGFloat = 0.975
    var pressedOpacity: Double = 0.9

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.72),
                value: configuration.isPressed
            )
    }
}
