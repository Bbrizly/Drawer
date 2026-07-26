import Carbon.HIToolbox
import XCTest
@testable import Drawer

final class HotkeyBindingTests: XCTestCase {
    /// The old switch and a tap shortcut both toggled the drawer, so a Mac with
    /// both on opened and shut it on one tap. The switch has to fold in.
    func testRightCommandTapMigrationBecomesTheShortcut() {
        withSavedShortcut {
            let defaults = UserDefaults.standard
            HotkeyBinding.ctrlOptSpace.save()
            defaults.set(true, forKey: "rightCommandTapEnabled")

            HotkeyBinding.migrateRightCommandTap()

            XCTAssertEqual(HotkeyBinding.saved, .tap(UInt32(kVK_RightCommand)))
            XCTAssertFalse(defaults.bool(forKey: "rightCommandTapEnabled"))
        }
    }

    /// Someone already on a tap keeps the one they picked.
    func testRightCommandTapMigrationLeavesAnExistingTapAlone() {
        withSavedShortcut {
            let defaults = UserDefaults.standard
            HotkeyBinding.tap(UInt32(kVK_RightOption)).save()
            defaults.set(true, forKey: "rightCommandTapEnabled")

            HotkeyBinding.migrateRightCommandTap()

            XCTAssertEqual(HotkeyBinding.saved, .tap(UInt32(kVK_RightOption)))
        }
    }

    /// A tap of a key that carries no modifier flag can never fire, and Carbon
    /// will not take it either, so it must not leave the app with no shortcut.
    func testSavedFallsBackWhenTheTappedKeyIsNotAModifier() {
        withSavedShortcut {
            HotkeyBinding(keyCode: UInt32(kVK_ANSI_D), modifiers: HotkeyBinding.tapMarker).save()
            XCTAssertEqual(HotkeyBinding.saved, .ctrlOptSpace)
        }
    }

    private func withSavedShortcut(_ body: () -> Void) {
        let defaults = UserDefaults.standard
        let keys = ["hotkeyKeyCode", "hotkeyModifiers", "rightCommandTapEnabled"]
        let prior = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, prior) {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
        body()
    }

    func testSingleKeyLabel() {
        let binding = HotkeyBinding(keyCode: UInt32(kVK_F13), modifiers: 0)
        XCTAssertEqual(binding.label, "F13")
        XCTAssertTrue(binding.isSingleKey)
        XCTAssertFalse(binding.isTypingKey)
    }

    func testModifierLabel() {
        XCTAssertEqual(HotkeyBinding.ctrlOptSpace.label, "⌃⌥Space")
    }

    /// Letter and number keys used to fall through to their raw code, so ⌘K
    /// read as "⌘Key 40" in the field.
    func testTypingKeyLabels() {
        XCTAssertEqual(
            HotkeyBinding(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey)).label, "⌘K")
        XCTAssertEqual(HotkeyBinding(keyCode: UInt32(kVK_ANSI_7), modifiers: 0).label, "7")
        XCTAssertEqual(HotkeyBinding(keyCode: UInt32(kVK_ANSI_Slash), modifiers: 0).label, "/")
    }

    /// Two modifiers cannot be a shortcut on their own, so the field must stop
    /// promising that letting go of them works.
    func testRecordingHint() {
        XCTAssertEqual(
            HotkeyRecorderField.recordingHint([.control]),
            "Add a key, or let go to use ⌃ alone.")
        XCTAssertEqual(
            HotkeyRecorderField.recordingHint([.control, .option]),
            "Now press a key to finish the shortcut.")
        XCTAssertEqual(
            HotkeyRecorderField.recordingHint([]), "Press any keys. One modifier alone works.")
    }

    func testTappedModifierIsOneCap() {
        let binding = HotkeyBinding.tap(UInt32(kVK_RightCommand))
        XCTAssertEqual(binding.parts, ["right ⌘"])
        XCTAssertTrue(binding.isModifierTap)
        XCTAssertEqual(binding.tapFlag, .command)
        XCTAssertTrue(binding.needsAccessibility)
        XCTAssertNil(binding.problem)
    }

    func testTappedModifierSurvivesASaveAndLoad() {
        let defaults = UserDefaults.standard
        let priorCode = defaults.object(forKey: "hotkeyKeyCode")
        let priorMods = defaults.object(forKey: "hotkeyModifiers")

        let binding = HotkeyBinding.tap(UInt32(kVK_Option))
        binding.save()
        XCTAssertEqual(HotkeyBinding.saved, binding)
        XCTAssertTrue(HotkeyBinding.saved.isModifierTap)

        if let priorCode {
            defaults.set(priorCode, forKey: "hotkeyKeyCode")
        } else {
            defaults.removeObject(forKey: "hotkeyKeyCode")
        }
        if let priorMods {
            defaults.set(priorMods, forKey: "hotkeyModifiers")
        } else {
            defaults.removeObject(forKey: "hotkeyModifiers")
        }
    }

    func testAKeyIsNotATappableModifier() {
        XCTAssertNil(HotkeyBinding.tap(UInt32(kVK_ANSI_A)).tapFlag)
        XCTAssertNotNil(HotkeyBinding.tap(UInt32(kVK_ANSI_A)).problem)
    }

    func testLetterKeyIsTypingKey() {
        let binding = HotkeyBinding(keyCode: UInt32(kVK_ANSI_A), modifiers: 0)
        XCTAssertTrue(binding.isTypingKey)
    }

    func testSaveAndLoad() {
        let defaults = UserDefaults.standard
        let priorCode = defaults.object(forKey: "hotkeyKeyCode")
        let priorMods = defaults.object(forKey: "hotkeyModifiers")

        let binding = HotkeyBinding(keyCode: UInt32(kVK_F15), modifiers: 0)
        binding.save()
        XCTAssertEqual(HotkeyBinding.saved, binding)

        if let priorCode {
            defaults.set(priorCode, forKey: "hotkeyKeyCode")
        } else {
            defaults.removeObject(forKey: "hotkeyKeyCode")
        }
        if let priorMods {
            defaults.set(priorMods, forKey: "hotkeyModifiers")
        } else {
            defaults.removeObject(forKey: "hotkeyModifiers")
        }
    }
}
