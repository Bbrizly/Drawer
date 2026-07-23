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
